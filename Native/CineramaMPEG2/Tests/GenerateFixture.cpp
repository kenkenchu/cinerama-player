// Locally generated test media; no third-party footage or Plex connection.
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
}
#include <cmath>
#include <cstdio>
#include <cstdlib>
// Link the patched library without enabling the experimental decoder in this
// encoder-only tool. Opaque is never set, so these hooks must never be called.
extern "C" void cinerama_mpeg2_idct_configure(void *,AVCodecContext *) { abort(); }
extern "C" void cinerama_mpeg2_idct_flush(void *) { abort(); }
static void check(int r) { if(r<0) { char e[128]; av_strerror(r,e,sizeof(e)); fprintf(stderr,"Fixture error: %s\n",e); exit(1); } }
int main(int argc,char **argv) {
    if(argc!=5) return 2;
    const char *path=argv[1]; int interlaced=atoi(argv[2]), chroma422=atoi(argv[3]), hd=atoi(argv[4]);
    AVFormatContext *mux=nullptr;
    check(avformat_alloc_output_context2(&mux,nullptr,strstr(path,".m3u8")?"hls":"mpegts",path));
    AVCodecContext *v=avcodec_alloc_context3(avcodec_find_encoder(AV_CODEC_ID_MPEG2VIDEO));
    v->width=hd?1920:320; v->height=hd?1080:240; v->time_base={1,30}; v->framerate={30,1};
    v->pix_fmt=chroma422?AV_PIX_FMT_YUV422P:AV_PIX_FMT_YUV420P; v->bit_rate=hd?12000000:1500000;
    v->gop_size=12; v->max_b_frames=2; v->thread_count=1;
    if(chroma422) v->profile=AV_PROFILE_MPEG2_422;
    if(interlaced) v->flags|=AV_CODEC_FLAG_INTERLACED_DCT|AV_CODEC_FLAG_INTERLACED_ME;
    check(avcodec_open2(v,v->codec,nullptr));
    AVStream *vs=avformat_new_stream(mux,nullptr); vs->time_base=v->time_base;
    check(avcodec_parameters_from_context(vs->codecpar,v));
    AVCodecContext *a=avcodec_alloc_context3(avcodec_find_encoder(AV_CODEC_ID_AC3));
    a->sample_fmt=AV_SAMPLE_FMT_FLTP; a->sample_rate=48000; a->time_base={1,48000}; a->bit_rate=192000;
    a->ch_layout=AV_CHANNEL_LAYOUT_STEREO;
    check(avcodec_open2(a,a->codec,nullptr));
    AVStream *as=avformat_new_stream(mux,nullptr); as->time_base=a->time_base;
    check(avcodec_parameters_from_context(as->codecpar,a));
    if(!(mux->oformat->flags&AVFMT_NOFILE)) check(avio_open(&mux->pb,path,AVIO_FLAG_WRITE));
    AVDictionary *options=nullptr;
    av_dict_set(&options,"hls_time","1",0); av_dict_set(&options,"hls_list_size","0",0);
    check(avformat_write_header(mux,&options)); av_dict_free(&options);
    auto encode=[&](AVCodecContext *context,AVStream *stream,AVFrame *frame) {
        check(avcodec_send_frame(context,frame)); AVPacket *p=av_packet_alloc();
        int r;
        while((r=avcodec_receive_packet(context,p))>=0) {
            av_packet_rescale_ts(p,context->time_base,stream->time_base); p->stream_index=stream->index;
            check(av_interleaved_write_frame(mux,p)); av_packet_unref(p);
        }
        if(r!=AVERROR_EOF && r!=AVERROR(EAGAIN)) check(r);
        av_packet_free(&p);
    };
    AVFrame *vf=av_frame_alloc(); vf->width=v->width; vf->height=v->height; vf->format=v->pix_fmt;
    check(av_frame_get_buffer(vf,32));
    AVFrame *af=av_frame_alloc(); af->nb_samples=a->frame_size; af->sample_rate=48000; af->format=a->sample_fmt;
    check(av_channel_layout_copy(&af->ch_layout,&a->ch_layout)); check(av_frame_get_buffer(af,0));
    int64_t audioPTS=0;
    for(int n=0;n<90;n++) {
        check(av_frame_make_writable(vf)); vf->pts=n;
        if(interlaced) vf->flags=AV_FRAME_FLAG_INTERLACED|AV_FRAME_FLAG_TOP_FIELD_FIRST;
        for(int plane=0;plane<3;plane++) {
            int w=plane?v->width/2:v->width, h=plane&&!chroma422?v->height/2:v->height;
            for(int y=0;y<h;y++) for(int x=0;x<w;x++) {
                // Spatial AC, translating shapes, and distinct field samples.
                int shift=n*3+(interlaced?(y%2)*2:0);
                int value=plane?128+int(35*sin((x+y+n)*0.05+plane)):
                    96+int(40*sin((x+shift)*0.07)+35*cos((y+n)*0.08))+(((x+shift)/32+y/32)%2)*25;
                vf->data[plane][y*vf->linesize[plane]+x]=uint8_t(value);
            }
        }
        encode(v,vs,vf);
        while(audioPTS<((n+1)*48000/30)) {
            check(av_frame_make_writable(af)); af->pts=audioPTS;
            for(int ch=0;ch<2;ch++) for(int i=0;i<af->nb_samples;i++)
                ((float *)af->extended_data[ch])[i]=float(0.1*sin(2*M_PI*(440+ch*110)*(audioPTS+i)/48000));
            encode(a,as,af); audioPTS+=af->nb_samples;
        }
    }
    encode(v,vs,nullptr); encode(a,as,nullptr); check(av_write_trailer(mux));
    av_frame_free(&vf); av_frame_free(&af); avcodec_free_context(&v); avcodec_free_context(&a);
    if(!(mux->oformat->flags&AVFMT_NOFILE)) avio_closep(&mux->pb);
    avformat_free_context(mux);
}
