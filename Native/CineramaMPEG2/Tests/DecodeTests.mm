#import <Foundation/Foundation.h>
#include "CineramaMPEG2.h"
#include <vector>
#include <cmath>
#include <cstdio>
#include <cstdlib>
struct Frame { std::vector<uint8_t> pixels; CMTime pts; };
struct Result { std::vector<Frame> frames; int audio=0; uint64_t blocks=0; double elapsed=0,gpu=0; };
static void require(bool value,const char *message) { if(!value) { fprintf(stderr,"FAIL: %s\n",message); exit(1); } }
static Result decode(const char *path,bool metal) {
    Result r; CM2Decoder *d=cm2_create(metal); require(d,"create");
    double start=CFAbsoluteTimeGetCurrent();
    if(cm2_open(d,path)<0) { fprintf(stderr,"%s\n",cm2_error(d)); exit(1); }
    CMTime lastAudio=kCMTimeInvalid;
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
            CMTime pts=CMSampleBufferGetPresentationTimeStamp(sample);
            if(CMTIME_IS_VALID(lastAudio)) require(CMTimeCompare(pts,lastAudio)>0,"ordered audio timestamps");
            lastAudio=pts;
            require(CMSampleBufferGetNumSamples(sample)>0,"audio samples"); r.audio++;
        }
        CFRelease(sample);
    }
    r.elapsed=CFAbsoluteTimeGetCurrent()-start; r.blocks=cm2_gpu_blocks(d); r.gpu=cm2_gpu_seconds(d); cm2_close(d); return r;
}
int main(int argc,char **argv) {
    @autoreleasepool {
        require(argc==2,"fixture argument");
        Result cpu=decode(argv[1],false), gpu=decode(argv[1],true);
        require(cpu.frames.size()==90 && gpu.frames.size()==90,"all 90 I/P/B frames decoded");
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
        CM2Decoder *d=cm2_create(1); cm2_cancel(d); require(cm2_open(d,argv[1])<0,"cancel interrupts input"); cm2_close(d);
        d=cm2_create(0); require(cm2_open(d,"/nonexistent/cinerama-fixture.ts")<0,"missing input fails safely"); cm2_close(d);
    }
}
