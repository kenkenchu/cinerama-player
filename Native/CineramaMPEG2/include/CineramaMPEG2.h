#ifndef CINERAMA_MPEG2_H
#define CINERAMA_MPEG2_H
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct CM2Decoder CM2Decoder;
// All operations except cancel and request_audio run serially on ONE worker thread.
CM2Decoder *cm2_create(int metal);
int cm2_open(CM2Decoder *, const char *url);
// 1 video, 2 audio, 0 EOF, -1 failure. Samples are returned retained.
int cm2_read(CM2Decoder *, CMSampleBufferRef *sample);
CMSampleBufferRef cm2_next(CM2Decoder *, int *kind) CF_RETURNS_RETAINED;
void cm2_cancel(CM2Decoder *);
void cm2_close(CM2Decoder *);
int cm2_has_audio(CM2Decoder *);
int cm2_audio_track_count(CM2Decoder *);
int cm2_audio_track_id(CM2Decoder *,int position);
int cm2_audio_track_channels(CM2Decoder *,int position);
const char *cm2_audio_track_language(CM2Decoder *,int position);
const char *cm2_audio_track_codec(CM2Decoder *,int position);
int cm2_audio_track_supported(CM2Decoder *,int position);
int cm2_selected_audio(CM2Decoder *);
void cm2_request_audio(CM2Decoder *,int stream_id);
uint64_t cm2_gpu_blocks(CM2Decoder *);
double cm2_gpu_seconds(CM2Decoder *);
int cm2_retryable(CM2Decoder *);
const char *cm2_error(CM2Decoder *);
#ifdef __cplusplus
}
#endif
#endif
