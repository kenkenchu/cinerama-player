#import <Foundation/Foundation.h>
#include "CineramaMPEG2.h"
#include <vector>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <AudioToolbox/AudioToolbox.h>
#include <cstring>
#include <thread>
#include <chrono>
#include <mach/mach.h>
struct Frame { std::vector<uint8_t> pixels; CMTime pts; };
struct Result { std::vector<Frame> frames; int audio=0; uint64_t blocks=0; double elapsed=0,gpu=0; };
static void require(bool value,const char *message) { if(!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
static Result decode(const char *path,bool metal,int expectedChannels) {
    Result r; CM2Decoder *d=cm2_create(metal); require(d,"create");
    double start=CFAbsoluteTimeGetCurrent();
    if(cm2_open(d,path)<0) { fprintf(stderr,"%s\n",cm2_error(d)); exit(1); }
    CMTime lastAudio=kCMTimeInvalid, lastAudioEnd=kCMTimeInvalid;
    while(true) {
        int kind=0; CMSampleBufferRef sample=cm2_next(d,&kind);
        if(!sample) { if(kind<0) fprintf(stderr,"%s\n",cm2_error(d)); require(kind==0,"decode"); break; }
        require(CMSampleBufferDataIsReady(sample),"sample data ready");
        if(kind==1) {
            CVPixelBufferRef pixel=CMSampleBufferGetImageBuffer(sample);
            require(pixel,"pixel buffer"); CVPixelBufferLockBaseAddress(pixel,kCVPixelBufferLock_ReadOnly);
            Frame f; f.pts=CMSampleBufferGetPresentationTimeStamp(sample);
            for(size_t plane=0;plane<2;plane++) {
                size_t w=CVPixelBufferGetWidthOfPlane(pixel,plane)*(plane?2:1);
                size_t h=CVPixelBufferGetHeightOfPlane(pixel,plane), stride=CVPixelBufferGetBytesPerRowOfPlane(pixel,plane);
                uint8_t *p=(uint8_t *)CVPixelBufferGetBaseAddressOfPlane(pixel,plane);
                for(size_t y=0;y<h;y++) f.pixels.insert(f.pixels.end(),p+y*stride,p+y*stride+w);
            }
            CVPixelBufferUnlockBaseAddress(pixel,kCVPixelBufferLock_ReadOnly);
            if(!r.frames.empty()) require(CMTimeCompare(f.pts,r.frames.back().pts)>0,"ordered video timestamps");
            r.frames.push_back(std::move(f));
        } else {
            CMAudioFormatDescriptionRef format=CMSampleBufferGetFormatDescription(sample);
            const AudioStreamBasicDescription *asbd=CMAudioFormatDescriptionGetStreamBasicDescription(format);
            require(asbd && asbd->mChannelsPerFrame==(unsigned)expectedChannels && asbd->mSampleRate==48000,"preserved PCM channel count and sample rate");
            size_t layoutSize=0;
            const AudioChannelLayout *layout=CMAudioFormatDescriptionGetChannelLayout(format,&layoutSize);
            require(layout && layout->mNumberChannelDescriptions==(unsigned)expectedChannels,"explicit PCM channel mapping");
            CMTime pts=CMSampleBufferGetPresentationTimeStamp(sample);
            if(CMTIME_IS_VALID(lastAudio)) require(CMTimeCompare(pts,lastAudio)>0,"ordered audio timestamps");
            if(CMTIME_IS_VALID(lastAudioEnd)) require(fabs(CMTimeGetSeconds(CMTimeSubtract(pts,lastAudioEnd)))<0.00003,"continuous PCM timestamps");
            CMTime duration=CMSampleBufferGetDuration(sample);
            require(CMTIME_IS_NUMERIC(duration) && CMTimeGetSeconds(duration)>0,"positive aggregate PCM duration");
            lastAudioEnd=CMTimeAdd(pts,duration);
            lastAudio=pts;
            require(CMSampleBufferGetNumSamples(sample)>0,"audio samples"); r.audio++;
        }
        CFRelease(sample);
    }
    r.elapsed=CFAbsoluteTimeGetCurrent()-start; r.blocks=cm2_gpu_blocks(d); r.gpu=cm2_gpu_seconds(d); cm2_close(d); return r;
}
// Streaming validation deliberately retains no decoded frames. RSS is sampled
// after warmup; this tests decoder ownership, not AVFoundation renderer queues.
static uint64_t residentBytes() {
    mach_task_basic_info_data_t info{};
    mach_msg_type_number_t count=MACH_TASK_BASIC_INFO_COUNT;
    require(task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&info,&count)==KERN_SUCCESS,"read resident memory");
    return info.resident_size;
}
static void soak(const char *path, bool metal, int expectedFrames) {
    CM2Decoder *d=cm2_create(metal); require(d && cm2_open(d,path)==0,"open soak fixture");
    int video=0,audio=0; uint64_t baseline=0,peak=0;
    CMTime lastVideo=kCMTimeInvalid,lastAudioEnd=kCMTimeInvalid;
    double start=CFAbsoluteTimeGetCurrent();
    while(true) {
        @autoreleasepool {
            int kind=0; CMSampleBufferRef sample=cm2_next(d,&kind);
            if(!sample) { require(kind==0,"soak decode completes without failure"); break; }
            CMTime pts=CMSampleBufferGetPresentationTimeStamp(sample);
            require(CMTIME_IS_NUMERIC(pts),"numeric soak timestamp");
            if(kind==1) {
                if(CMTIME_IS_VALID(lastVideo)) require(fabs(CMTimeGetSeconds(CMTimeSubtract(pts,lastVideo))-1.0/60)<0.00001,"sustained field cadence");
                lastVideo=pts; video++;
            } else {
                if(CMTIME_IS_VALID(lastAudioEnd)) require(fabs(CMTimeGetSeconds(CMTimeSubtract(pts,lastAudioEnd)))<0.00003,"sustained contiguous PCM");
                lastAudioEnd=CMTimeAdd(pts,CMSampleBufferGetDuration(sample)); audio++;
            }
            CFRelease(sample);
            if(video>=300 && video%60==0) {
                uint64_t rss=residentBytes();
                if(!baseline) baseline=rss;
                peak=std::max(peak,rss);
                require(peak-baseline<64ULL*1024*1024,"post-warmup RSS growth stays below 64 MiB");
            }
        }
    }
    require(video==expectedFrames && audio>0 && baseline>0,"complete sustained video/audio and memory observations");
    require(metal ? cm2_gpu_blocks(d)>100 : cm2_gpu_blocks(d)==0,"soak uses requested IDCT mode");
    printf("soak: mode=%s frames=%d audio=%d elapsed=%.3fs baselineRSS=%.2fMiB peakRSS=%.2fMiB growth=%.2fMiB\n",
        metal?"Metal":"CPU",video,audio,CFAbsoluteTimeGetCurrent()-start,baseline/1048576.0,peak/1048576.0,(peak-baseline)/1048576.0);
    cm2_close(d);
}
int main(int argc,char **argv) {
    @autoreleasepool {
        if(argc==5 && strcmp(argv[1],"--soak")==0) {
            require(strcmp(argv[3],"cpu")==0 || strcmp(argv[3],"metal")==0,"explicit soak mode");
            soak(argv[2],strcmp(argv[3],"metal")==0,atoi(argv[4])); return 0;
        }
        if(argc==3 && strcmp(argv[1],"--cancel")==0) {
            CM2Decoder *d=cm2_create(0); int result=0; double start=CFAbsoluteTimeGetCurrent();
            std::thread worker([&] { result=cm2_open(d,argv[2]); });
            std::this_thread::sleep_for(std::chrono::milliseconds(200)); cm2_cancel(d); worker.join();
            require(result<0 && CFAbsoluteTimeGetCurrent()-start<2,"cancel interrupts in-flight network IO");
            cm2_close(d); puts("In-flight IO cancellation passed"); return 0;
        }
        if(argc==3 && strcmp(argv[1],"--failure")==0) {
            CM2Decoder *d=cm2_create(0); bool failed=cm2_open(d,argv[2])<0;
            for(int n=0;!failed && n<1000;n++) {
                int kind; CMSampleBufferRef sample=cm2_next(d,&kind);
                if(sample) CFRelease(sample); else { failed=kind<0; break; }
            }
            require(failed && cm2_retryable(d),"recoverable network/format failure classification");
            cm2_close(d); puts("Recoverable input failure classification passed"); return 0;
        }
        require(argc>=2 && argc<=4,"fixture argument");
        size_t expectedFrames=argc>=3?atoi(argv[2]):90;
        int channels=argc==4?atoi(argv[3]):2;
        Result cpu=decode(argv[1],false,channels), gpu=decode(argv[1],true,channels);
        require(cpu.frames.size()==expectedFrames && gpu.frames.size()==expectedFrames,"all frames including field-rate outputs decoded");
        for(size_t i=1;i<gpu.frames.size();i++) {
            double delta=CMTimeGetSeconds(CMTimeSubtract(gpu.frames[i].pts,gpu.frames[i-1].pts));
            require(fabs(delta-(expectedFrames==180?1.0/60:1.0/30))<0.00001,"progressive/field output cadence");
        }
        require(cpu.audio>80 && cpu.audio==gpu.audio,"audio present in both modes");
        require(cpu.blocks==0 && gpu.blocks>100,"Metal actually executed IDCT");
        double squared=0; uint64_t samples=0; int maxError=0;
        for(size_t n=0;n<cpu.frames.size();n++) {
            const Frame &a=cpu.frames[n], &b=gpu.frames[n];
            require(CMTimeCompare(a.pts,b.pts)==0,"matching timestamps"); require(a.pixels.size()==b.pixels.size(),"matching plane sizes");
            for(size_t p=0;p<a.pixels.size();p++) { int e=abs(int(a.pixels[p])-int(b.pixels[p])); squared+=e*e; maxError=std::max(maxError,e); samples++; }
        }
        double psnr=squared==0?INFINITY:10*log10(255.0*255.0/(squared/samples));
        printf("decode: frames=%zu audio=%d blocks=%llu PSNR=%.2f dB maxError=%d CPU=%.3fs Metal=%.3fs GPU=%.3fs\n",gpu.frames.size(),gpu.audio,(unsigned long long)gpu.blocks,psnr,maxError,cpu.elapsed,gpu.elapsed,gpu.gpu);
        require(psnr>45 && maxError<=12,"CPU/Metal reconstruction fidelity");
        CM2Decoder *tracks=cm2_create(0); require(cm2_open(tracks,argv[1])==0,"open for track tests");
        if(cm2_audio_track_count(tracks)==2) {
            int first=cm2_audio_track_id(tracks,0), second=cm2_audio_track_id(tracks,1);
            require(strcmp(cm2_audio_track_language(tracks,0),"eng")==0 && strcmp(cm2_audio_track_language(tracks,1),"spa")==0,"track language metadata");
            for(int target: {second,first}) {
                cm2_request_audio(tracks,target);
                bool received=false;
                for(int n=0;n<500 && !received;n++) {
                    int kind; CMSampleBufferRef sample=cm2_next(tracks,&kind); require(sample,"read after audio selection");
                    if(kind==2) {
                        const AudioStreamBasicDescription *asbd=CMAudioFormatDescriptionGetStreamBasicDescription(CMSampleBufferGetFormatDescription(sample));
                        require(cm2_selected_audio(tracks)==target,"active selected audio stream");
                        require(asbd && asbd->mChannelsPerFrame==(target==second?2:6) && asbd->mSampleRate==(target==second?44100:48000),"channel/rate change after selection");
                        received=true;
                    }
                    CFRelease(sample);
                }
                require(received,"selected audio arrives");
            }
            cm2_request_audio(tracks,0); int kind=0; CMSampleBufferRef bad=cm2_next(tracks,&kind);
            require(!bad && kind<0,"invalid non-audio selection fails safely");
            puts("Audio track switching, language and 5.1/44.1kHz transitions passed");
        }
        cm2_close(tracks);
        CM2Decoder *d=cm2_create(1); cm2_cancel(d); require(cm2_open(d,argv[1])<0,"cancel interrupts input"); cm2_close(d);
        d=cm2_create(0); require(cm2_open(d,"/nonexistent/cinerama-fixture.ts")<0,"missing input fails safely"); cm2_close(d);
    }
}
