// Cinerama experimental hybrid MPEG-2 decoder. FFmpeg is LGPL-2.1-or-later;
// its source is fetched with a pinned checksum and patched by patch_ffmpeg.py.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <AudioToolbox/AudioToolbox.h>
#include "CineramaMPEG2.h"
#define restrict __restrict
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include "libavcodec/idctdsp.h"
#include "libavcodec/simple_idct.h"
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersrc.h>
#include <libavfilter/buffersink.h>
}
#undef restrict
#include <atomic>
#include <vector>
#include <cmath>
#include <cstring>

static const size_t capacity = 8192;
struct Target { uint8_t *destination; ptrdiff_t stride; };
struct CM2Decoder {
    bool metal;
    std::atomic<bool> cancelled{false};
    std::atomic<uint64_t> blocks{0};
    std::atomic<double> gpuTime{0};
    char error[192] = {};
    AVFormatContext *format = nullptr;
    NSString *authToken = nil;
    NSString *sourceHost = nil;
    NSNumber *sourcePort = nil;
    NSString *sourceScheme = nil;
    AVCodecContext *video = nullptr, *audio = nullptr;
    AVFrame *frame = nullptr;
    AVPacket *packet = nullptr;
    AVFilterGraph *filters = nullptr;
    AVFilterContext *filterInput = nullptr, *filterOutput = nullptr;
    AVFrame *filtered = nullptr;
    bool filterEOF = false;
    int filterWidth = 0, filterHeight = 0, filterFormat = -1;
    SwrContext *swr = nullptr;
    SwsContext *sws = nullptr;
    int videoIndex = -1, audioIndex = -1;
    AVCodecContext *pending = nullptr;
    int pendingKind = 0;
    bool draining = false;
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    id<MTLComputePipelineState> pipeline;
    id<MTLBuffer> coefficients, prediction, output, basis;
    std::vector<Target> targets;
};
static thread_local CM2Decoder *active = nullptr;
static void fail(CM2Decoder *d, const char *message) { snprintf(d->error,sizeof(d->error),"%s",message); }
static int interrupt(void *opaque) { return ((CM2Decoder *)opaque)->cancelled.load() ? 1 : 0; }

// Plex segment URLs may omit the top-level token. Carry it only to the same
// server origin, through query items rather than global headers. Never log URLs.
static int openIO(AVFormatContext *context, AVIOContext **io, const char *url,
                  int flags, AVDictionary **options) {
    CM2Decoder *d=(CM2Decoder *)context->opaque;
    @autoreleasepool {
        NSURLComponents *parts=[NSURLComponents componentsWithString:[NSString stringWithUTF8String:url]];
        if (d->authToken) {
            NSNumber *port=parts.port ?: ([parts.scheme isEqualToString:@"https"]?@443:@80);
            if (![parts.host.lowercaseString isEqualToString:d->sourceHost] ||
                ![port isEqualToNumber:d->sourcePort] || ![parts.scheme isEqualToString:d->sourceScheme])
                return AVERROR(EPERM);
            NSMutableArray<NSURLQueryItem *> *items=[parts.queryItems mutableCopy] ?: [NSMutableArray new];
            BOOL hasToken=NO;
            for (NSURLQueryItem *item in items) if ([item.name caseInsensitiveCompare:@"X-Plex-Token"]==NSOrderedSame) hasToken=YES;
            if (!hasToken) { [items addObject:[NSURLQueryItem queryItemWithName:@"X-Plex-Token" value:d->authToken]]; parts.queryItems=items; }
        }
        av_dict_set(options,"rw_timeout","10000000",0);
        return avio_open2(io,parts.URL.absoluteString.UTF8String,flags,&context->interrupt_callback,options);
    }
}

static const char *kernel = R"METAL(
#include <metal_stdlib>
using namespace metal;
kernel void reconstruct(device const short *c [[buffer(0)]], device const uchar *p [[buffer(1)]],
 device uchar *o [[buffer(2)]], device const float *basis [[buffer(3)]],
 uint b [[threadgroup_position_in_grid]], uint t [[thread_index_in_threadgroup]]) {
 threadgroup float rows[64];
 uint x=t%8, y=t/8;
 float r=0;
 for(uint u=0;u<8;u++) r+=float(c[b*64+y*8+u])*basis[x*8+u];
 rows[t]=r;
 threadgroup_barrier(mem_flags::mem_threadgroup);
 float value=0;
 for(uint v=0;v<8;v++) value+=rows[v*8+x]*basis[y*8+v];
 o[b*64+t]=uchar(clamp(int(floor(value+0.5f))+int(p[b*64+t]),0,255));
}
)METAL";

extern "C" void cinerama_mpeg2_idct_flush(void *opaque) {
    CM2Decoder *d = (CM2Decoder *)opaque;
    if (!d || d->targets.empty()) return;
    @autoreleasepool {
        id<MTLCommandBuffer> command = [d->queue commandBuffer];
        id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
        if (!command || !encoder) { fail(d,"Metal command allocation failed"); d->targets.clear(); return; }
        [encoder setComputePipelineState:d->pipeline];
        [encoder setBuffer:d->coefficients offset:0 atIndex:0];
        [encoder setBuffer:d->prediction offset:0 atIndex:1];
        [encoder setBuffer:d->output offset:0 atIndex:2];
        [encoder setBuffer:d->basis offset:0 atIndex:3];
        [encoder dispatchThreadgroups:MTLSizeMake(d->targets.size(),1,1) threadsPerThreadgroup:MTLSizeMake(64,1,1)];
        [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
        if (command.status != MTLCommandBufferStatusCompleted) {
            fail(d,"Metal reconstruction failed"); d->targets.clear(); return;
        }
        const uint8_t *pixels = (const uint8_t *)d->output.contents;
        for (size_t b=0;b<d->targets.size();b++) {
            Target t=d->targets[b];
            for (int y=0;y<8;y++) memcpy(t.destination+y*t.stride,pixels+b*64+y*8,8);
        }
        d->blocks.fetch_add(d->targets.size());
        d->gpuTime.store(d->gpuTime.load()+fmax(0,command.GPUEndTime-command.GPUStartTime));
        d->targets.clear();
    }
}
static void enqueue(uint8_t *destination, ptrdiff_t stride, int16_t *block, bool add) {
    CM2Decoder *d=active;
    if (!d) return; // Only installed for our serial, explicitly owned decoder.
    if (d->targets.size()==capacity) cinerama_mpeg2_idct_flush(d);
    size_t n=d->targets.size();
    memcpy((int16_t *)d->coefficients.contents+n*64,block,128);
    uint8_t *prediction=(uint8_t *)d->prediction.contents+n*64;
    for (int y=0;y<8;y++) {
        if(add) memcpy(prediction+y*8,destination+y*stride,8);
        else memset(prediction+y*8,0,8);
    }
    d->targets.push_back({destination,stride});
    // FFmpeg reuses its coefficient blocks; our queue owns a copy.
    memset(block,0,128);
}
static void put(uint8_t *dst,ptrdiff_t stride,int16_t *block) { enqueue(dst,stride,block,false); }
static void add(uint8_t *dst,ptrdiff_t stride,int16_t *block) { enqueue(dst,stride,block,true); }
extern "C" void cinerama_mpeg2_idct_configure(void *context, AVCodecContext *avctx) {
    CM2Decoder *d=(CM2Decoder *)avctx->opaque;
    if (!d || !d->metal) return;
    IDCTDSPContext *idsp=(IDCTDSPContext *)context;
    idsp->idct_put=put; idsp->idct_add=add;
    idsp->perm_type=FF_IDCT_PERM_NONE;
}

CM2Decoder *cm2_create(int metal) {
    CM2Decoder *d=new CM2Decoder(); d->metal=metal!=0;
    // FFmpeg diagnostics can contain credential-bearing URLs: never forward them.
    av_log_set_level(AV_LOG_QUIET);
    d->frame=av_frame_alloc(); d->filtered=av_frame_alloc(); d->packet=av_packet_alloc();
    if (!d->frame || !d->filtered || !d->packet) { cm2_close(d); return nullptr; }
    if (d->metal) {
        @autoreleasepool {
            d->device=MTLCreateSystemDefaultDevice(); d->queue=[d->device newCommandQueue];
            NSError *error=nil;
            MTLCompileOptions *options=[MTLCompileOptions new]; options.mathMode=MTLMathModeSafe;
            id<MTLLibrary> library=[d->device newLibraryWithSource:[NSString stringWithUTF8String:kernel] options:options error:&error];
            d->pipeline=[d->device newComputePipelineStateWithFunction:[library newFunctionWithName:@"reconstruct"] error:&error];
            d->coefficients=[d->device newBufferWithLength:capacity*128 options:MTLResourceStorageModeShared];
            d->prediction=[d->device newBufferWithLength:capacity*64 options:MTLResourceStorageModeShared];
            d->output=[d->device newBufferWithLength:capacity*64 options:MTLResourceStorageModeShared];
            float basis[64];
            for(int x=0;x<8;x++) for(int u=0;u<8;u++)
                basis[x*8+u]=(u==0?1/sqrt(2.0):1)*cos((2*x+1)*u*M_PI/16)/2;
            d->basis=[d->device newBufferWithBytes:basis length:sizeof(basis) options:MTLResourceStorageModeShared];
            if (!d->pipeline || !d->queue || !d->coefficients || !d->prediction || !d->output || !d->basis) {
                cm2_close(d); return nullptr;
            }
        }
    }
    return d;
}
int cm2_open(CM2Decoder *d,const char *url) {
    active=d;
    d->format=avformat_alloc_context();
    if(!d->format) { fail(d,"Demuxer allocation failed"); return -1; }
    d->format->interrupt_callback={interrupt,d};
    d->format->opaque=d; d->format->io_open=openIO;
    @autoreleasepool {
        NSURLComponents *parts=[NSURLComponents componentsWithString:[NSString stringWithUTF8String:url]];
        d->sourceHost=parts.host.lowercaseString; d->sourceScheme=parts.scheme;
        d->sourcePort=parts.port ?: ([parts.scheme isEqualToString:@"https"]?@443:@80);
        for(NSURLQueryItem *item in parts.queryItems)
            if([item.name caseInsensitiveCompare:@"X-Plex-Token"]==NSOrderedSame) d->authToken=item.value;
    }
    AVDictionary *options=nullptr;
    av_dict_set(&options,"rw_timeout","10000000",0);
    av_dict_set(&options,"protocol_whitelist","file,http,https,tcp,tls,crypto",0);
    av_dict_set(&options,"live_start_index","-3",0);
    int result=avformat_open_input(&d->format,url,nullptr,&options); av_dict_free(&options);
    if(result<0 || avformat_find_stream_info(d->format,nullptr)<0) { fail(d,"Could not open the experimental MPEG-2 stream"); return -1; }
    d->videoIndex=av_find_best_stream(d->format,AVMEDIA_TYPE_VIDEO,-1,-1,nullptr,0);
    d->audioIndex=av_find_best_stream(d->format,AVMEDIA_TYPE_AUDIO,-1,-1,nullptr,0);
    if(d->videoIndex<0 || d->format->streams[d->videoIndex]->codecpar->codec_id!=AV_CODEC_ID_MPEG2VIDEO) {
        fail(d,"Experimental decoder requires MPEG-2 video"); return -1;
    }
    for(int kind=1;kind<=2;kind++) {
        int index=kind==1?d->videoIndex:d->audioIndex;
        if(index<0) continue;
        AVCodecParameters *params=d->format->streams[index]->codecpar;
        const AVCodec *codec=avcodec_find_decoder(params->codec_id);
        AVCodecContext *context=codec?avcodec_alloc_context3(codec):nullptr;
        if(!context) { fail(d,"Unsupported audio or video decoder"); return -1; }
        if(kind==1) d->video=context; else d->audio=context;
        avcodec_parameters_to_context(context,params);
        context->thread_count=1; context->thread_type=0;
        context->max_pixels=2048*1200;
        if(kind==1 && d->metal) context->opaque=d;
        if(avcodec_open2(context,codec,nullptr)<0) { fail(d,"Could not initialize the experimental decoder"); return -1; }
    }
    return 0;
}
static bool prepareVideoFilter(CM2Decoder *d, AVFrame *frame) {
    if (d->filters) {
        if (d->filterWidth!=frame->width || d->filterHeight!=frame->height || d->filterFormat!=frame->format) {
            fail(d,"Video format changed; retune the channel"); return false;
        }
        return true;
    }
    if (frame->width<=0 || frame->height<=0 || frame->width>2048 || frame->height>1200 ||
        (frame->format!=AV_PIX_FMT_YUV420P && frame->format!=AV_PIX_FMT_YUV422P)) {
        fail(d,"Experimental decoder supports HD 8-bit MPEG-2 4:2:0/4:2:2 only"); return false;
    }
    d->filters=avfilter_graph_alloc();
    if(!d->filters) { fail(d,"Deinterlacer allocation failed"); return false; }
    d->filters->nb_threads=2;
    AVRational tb=d->format->streams[d->videoIndex]->time_base;
    AVRational sar=frame->sample_aspect_ratio.num>0?frame->sample_aspect_ratio:AVRational{1,1};
    AVRational fps=av_guess_frame_rate(d->format,d->format->streams[d->videoIndex],frame);
    char args[256];
    snprintf(args,sizeof(args),"video_size=%dx%d:pix_fmt=%d:time_base=%d/%d:pixel_aspect=%d/%d:frame_rate=%d/%d",
        frame->width,frame->height,frame->format,tb.num,tb.den,sar.num,sar.den,fps.num,fps.den);
    AVFilterContext *deinterlace=nullptr;
    if(avfilter_graph_create_filter(&d->filterInput,avfilter_get_by_name("buffer"),"source",args,nullptr,d->filters)<0 ||
       avfilter_graph_create_filter(&deinterlace,avfilter_get_by_name("bwdif"),"deinterlace","mode=send_field:parity=auto:deint=interlaced",nullptr,d->filters)<0 ||
       avfilter_graph_create_filter(&d->filterOutput,avfilter_get_by_name("buffersink"),"sink",nullptr,nullptr,d->filters)<0 ||
       avfilter_link(d->filterInput,0,deinterlace,0)<0 || avfilter_link(deinterlace,0,d->filterOutput,0)<0 ||
       avfilter_graph_config(d->filters,nullptr)<0) {
        fail(d,"Could not configure field-rate deinterlacing"); return false;
    }
    d->filterWidth=frame->width; d->filterHeight=frame->height; d->filterFormat=frame->format;
    return true;
}
static CMSampleBufferRef videoSample(CM2Decoder *d, AVFrame *f, CMTime pts) {
    if(f->width<=0 || f->height<=0 || f->width>2048 || f->height>1200 ||
       (f->format!=AV_PIX_FMT_YUV420P && f->format!=AV_PIX_FMT_YUV422P)) {
        fail(d,"Experimental decoder supports HD 8-bit MPEG-2 4:2:0/4:2:2 only"); return nullptr;
    }
    CVPixelBufferRef pixel=nullptr;
    NSDictionary *attributes=@{(id)kCVPixelBufferIOSurfacePropertiesKey:@{},(id)kCVPixelBufferMetalCompatibilityKey:@YES};
    if(CVPixelBufferCreate(nullptr,f->width,f->height,kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        (__bridge CFDictionaryRef)attributes,&pixel)!=kCVReturnSuccess) { fail(d,"Video buffer allocation failed"); return nullptr; }
    CVPixelBufferLockBaseAddress(pixel,0);
    uint8_t *planes[4]={(uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixel,0),(uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixel,1),nullptr,nullptr};
    int strides[4]={(int)CVPixelBufferGetBytesPerRowOfPlane(pixel,0),(int)CVPixelBufferGetBytesPerRowOfPlane(pixel,1),0,0};
    d->sws=sws_getCachedContext(d->sws,f->width,f->height,(AVPixelFormat)f->format,f->width,f->height,AV_PIX_FMT_NV12,SWS_POINT,nullptr,nullptr,nullptr);
    if(!d->sws) { CVPixelBufferUnlockBaseAddress(pixel,0); CFRelease(pixel); fail(d,"Video conversion unavailable"); return nullptr; }
    sws_scale(d->sws,f->data,f->linesize,0,f->height,planes,strides);
    CVPixelBufferUnlockBaseAddress(pixel,0);
    CFStringRef matrix=f->colorspace==AVCOL_SPC_BT709?kCVImageBufferYCbCrMatrix_ITU_R_709_2:kCVImageBufferYCbCrMatrix_ITU_R_601_4;
    CVBufferSetAttachment(pixel,kCVImageBufferYCbCrMatrixKey,matrix,kCVAttachmentMode_ShouldPropagate);
    AVRational sar=f->sample_aspect_ratio.num>0?f->sample_aspect_ratio:d->video->sample_aspect_ratio;
    if(sar.num>0 && sar.den>0) {
        NSDictionary *aspect=@{(id)kCVImageBufferPixelAspectRatioHorizontalSpacingKey:@(sar.num),
                               (id)kCVImageBufferPixelAspectRatioVerticalSpacingKey:@(sar.den)};
        CVBufferSetAttachment(pixel,kCVImageBufferPixelAspectRatioKey,(__bridge CFDictionaryRef)aspect,kCVAttachmentMode_ShouldPropagate);
    }
    CMVideoFormatDescriptionRef format=nullptr;
    CMVideoFormatDescriptionCreateForImageBuffer(nullptr,pixel,&format);
    CMSampleTimingInfo timing={kCMTimeInvalid,pts,kCMTimeInvalid};
    CMSampleBufferRef sample=nullptr;
    if(format) CMSampleBufferCreateReadyWithImageBuffer(nullptr,pixel,format,&timing,&sample);
    if(format) CFRelease(format); CFRelease(pixel);
    if(!sample) fail(d,"Video sample creation failed");
    return sample;
}
static CMSampleBufferRef audioSample(CM2Decoder *d,AVFrame *f,CMTime pts) {
    if(!d->swr) {
        AVChannelLayout stereo=AV_CHANNEL_LAYOUT_STEREO;
        if(swr_alloc_set_opts2(&d->swr,&stereo,AV_SAMPLE_FMT_FLT,48000,&f->ch_layout,(AVSampleFormat)f->format,f->sample_rate,0,nullptr)<0 || swr_init(d->swr)<0) {
            fail(d,"Audio conversion unavailable"); return nullptr;
        }
    }
    int count=swr_get_out_samples(d->swr,f->nb_samples);
    std::vector<float> samples(count*2);
    uint8_t *output=(uint8_t *)samples.data();
    count=swr_convert(d->swr,&output,count,(const uint8_t **)f->extended_data,f->nb_samples);
    if(count<=0) { fail(d,"Audio conversion failed"); return nullptr; }
    AudioStreamBasicDescription asbd={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};
    CMAudioFormatDescriptionRef format=nullptr;
    CMAudioFormatDescriptionCreate(nullptr,&asbd,0,nullptr,0,nullptr,nullptr,&format);
    CMBlockBufferRef block=nullptr;
    size_t length=count*8;
    CMBlockBufferCreateWithMemoryBlock(nullptr,nullptr,length,nullptr,nullptr,0,length,0,&block);
    if(block) CMBlockBufferReplaceDataBytes(samples.data(),block,0,length);
    CMSampleTimingInfo timing={CMTimeMake(1,48000),pts,kCMTimeInvalid};
    size_t size=8; CMSampleBufferRef sample=nullptr;
    if(block && format) CMSampleBufferCreateReady(nullptr,block,format,count,1,&timing,1,&size,&sample);
    if(block) CFRelease(block); if(format) CFRelease(format);
    if(!sample) fail(d,"Audio sample creation failed");
    return sample;
}
int cm2_read(CM2Decoder *d,CMSampleBufferRef *sample) {
    active=d; *sample=nullptr;
    while(!d->cancelled.load() && !d->error[0]) {
        if(d->filterOutput) {
            int filtered=av_buffersink_get_frame(d->filterOutput,d->filtered);
            if(filtered>=0) {
                AVRational tb=av_buffersink_get_time_base(d->filterOutput);
                CMTime pts=CMTimeMake(av_rescale_q(d->filtered->pts,tb,{1,1000000}),1000000);
                *sample=videoSample(d,d->filtered,pts); av_frame_unref(d->filtered);
                return *sample?1:-1;
            }
            if(filtered!=AVERROR(EAGAIN) && filtered!=AVERROR_EOF) { fail(d,"Deinterlacing failed"); return -1; }
        }
        if(d->pending) {
            int result=avcodec_receive_frame(d->pending,d->frame);
            cinerama_mpeg2_idct_flush(d);
            if(d->error[0]) return -1;
            if(result>=0) {
                int kind=d->pendingKind, index=kind==1?d->videoIndex:d->audioIndex;
                int64_t timestamp=d->frame->best_effort_timestamp;
                if(timestamp==AV_NOPTS_VALUE) { av_frame_unref(d->frame); fail(d,"Missing media timestamp"); return -1; }
                AVRational tb=d->format->streams[index]->time_base;
                CMTime pts=CMTimeMake(av_rescale_q(timestamp,tb,{1,1000000}),1000000);
                if(kind==1) {
                    if(!prepareVideoFilter(d,d->frame)) return -1;
                    d->frame->pts=timestamp;
                    int fed=av_buffersrc_add_frame_flags(d->filterInput,d->frame,AV_BUFFERSRC_FLAG_KEEP_REF);
                    av_frame_unref(d->frame);
                    if(fed<0) { fail(d,"Video filter input failed"); return -1; }
                    continue;
                }
                *sample=audioSample(d,d->frame,pts);
                av_frame_unref(d->frame);
                return *sample?kind:-1;
            }
            if(result!=AVERROR(EAGAIN) && result!=AVERROR_EOF) { fail(d,"MPEG-2/audio decode failed"); return -1; }
            d->pending=nullptr;
        }
        if(d->draining) {
            if(d->filterInput && !d->filterEOF) {
                int fed=av_buffersrc_add_frame_flags(d->filterInput,nullptr,0);
                if(fed<0) { fail(d,"Video filter drain failed"); return -1; }
                d->filterEOF=true; continue;
            }
            return 0;
        }
        int result=av_read_frame(d->format,d->packet);
        if(result<0) {
            if(result!=AVERROR_EOF) { fail(d,"Live stream read failed"); return -1; }
            d->draining=true;
            avcodec_send_packet(d->video,nullptr); d->pending=d->video; d->pendingKind=1;
            continue;
        }
        AVCodecContext *context=d->packet->stream_index==d->videoIndex?d->video:
            d->packet->stream_index==d->audioIndex?d->audio:nullptr;
        int kind=d->packet->stream_index==d->videoIndex?1:2;
        if(context) {
            result=avcodec_send_packet(context,d->packet);
            cinerama_mpeg2_idct_flush(d);
            if(result<0) { av_packet_unref(d->packet); fail(d,"Compressed packet decode failed"); return -1; }
            d->pending=context; d->pendingKind=kind;
        }
        av_packet_unref(d->packet);
    }
    return -1;
}
CMSampleBufferRef cm2_next(CM2Decoder *d,int *kind) {
    @autoreleasepool { CMSampleBufferRef sample=nullptr; *kind=cm2_read(d,&sample); return sample; }
}
void cm2_cancel(CM2Decoder *d) { if(d) d->cancelled.store(true); }
void cm2_close(CM2Decoder *d) {
    if(!d) return;
    avcodec_free_context(&d->video); avcodec_free_context(&d->audio);
    avformat_close_input(&d->format); av_frame_free(&d->frame); av_frame_free(&d->filtered); av_packet_free(&d->packet);
    avfilter_graph_free(&d->filters);
    swr_free(&d->swr); sws_freeContext(d->sws);
    if(active==d) active=nullptr;
    delete d;
}
int cm2_has_audio(CM2Decoder *d) { return d->audioIndex>=0; }
uint64_t cm2_gpu_blocks(CM2Decoder *d) { return d->blocks.load(); }
double cm2_gpu_seconds(CM2Decoder *d) { return d->gpuTime.load(); }
const char *cm2_error(CM2Decoder *d) { return d->error[0]?d->error:"Experimental decoder stopped"; }
