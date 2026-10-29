# Real-stream MPEG-2 CPU/Metal experiment (macOS and tvOS)

This opt-in player decodes real MPEG-2 streams. It builds on the isolated
[reconstruction experiment](../MetalMPEG2Prototype/README.md), but adds a patched
FFmpeg decoder, HLS demuxing, PCM audio and native sample-buffer rendering. It is
for HD SDR MPEG-2. Mac keeps Standard playback by default; TV Live TV uses CPU decoding
without an opt-in toggle. TV has a separate native host and controls;
see [TV Live TV](../../docs/tvos-live-tv.md).

## User test

The decoder selector and Cmd-I instructions below apply to Mac. TV uses its
Live TV tab and More → Playback Information.

Quit and reopen the signed Cinerama build after rebuilding. In **Settings → Live
TV decoding experiment → MPEG-2 decoder**, select **Experimental CPU** or
**Experimental Metal**, then tune an MPEG-2 channel. Changes take effect on the
next tune; do not compare different channels. **Standard playback** returns to the
normal resolver/VLC player. Forced AVPlayer, forced VLC and AirPlay take priority.
The same confirmed copy-only Plex session URL is passed to the experimental
player; no extra tuner or server encoding request is created.

Cmd-I shows the actual decoder, GPU reconstructed-block count and accumulated
GPU command time. Metal mode must show an increasing block count; CPU mode must
show zero. Both modes use the same demux, audio conversion, rendering and clocks.
Compare CPU load after startup has settled. Total app load and energy matter
more than GPU execution time alone.

Experimental limits are visible in Settings: no captions or spatial audio.
Audio tracks can be selected; PCM preserves supported source layouts and rates. DVR is explicitly out of
scope; seek/skip stay disabled and the Mac player omits Go Live. BWDIF converts interlaced frames to
progressive field-rate output with automatic TFF/BFF parity; progressive frames
pass through at their original cadence. Deinterlacing runs on CPU in both modes.
Retryable network/input failures reconnect to the existing session with a
three-attempt budget; permanent errors stay visible. Choose Standard playback
and retune if recovery fails.
There is no silent CPU fallback that could invalidate an A/B test.

## Decoder boundary

- FFmpeg 8.0.1 handles HLS/MPEG-TS, MPEG-2 syntax, inverse quantization, scan and
  mismatch control, reference ordering, chroma and frame/field motion prediction.
  Motion compensation and parsing remain on the CPU in **both** modes.
- A small patch installs our natural-order IDCT callbacks only when an MPEG-2
  context has our explicit opaque owner. Other codecs and VLC are untouched.
- Metal mode copies inverse-quantized blocks and CPU-produced prediction pixels
  into reusable shared buffers. One 64-thread group performs a separable 8x8
  float IDCT, adds prediction and saturates each block. Both luma and chroma
  blocks execute on the GPU. Intra blocks have no JPEG-style +128 bias.
- Work is committed at completed macroblock rows and again before receiving
  decoded frames. Strided destinations preserve interlaced DCT layout. Row
  completion is required before first-field pixels may become references.
- FFmpeg slice/frame threading is disabled for this experiment. A thread-local
  owner is reset on each synchronous read, so Swift executor thread migration
  between reads does not change callback ownership. Per-decoder buffers never
  cross workers. Cancelling input uses FFmpeg's atomic interrupt callback.
- A bounded row batch (8192 blocks) and input dimension limits bound native GPU
  staging. Output is converted to video-range NV12 and retained CMSampleBuffers.
  A bounded FFmpeg BWDIF filter precedes NV12 conversion.
  AC3/EAC3/AAC/MP2 audio is decoded locally to interleaved float PCM at the
  source rate, preserving supported mono through 7.1 layouts with explicit
  Core Audio channel labels. Unknown layouts fail explicitly. Unsupported codecs fail rather than requesting Plex conversion.
- TV opts into two seconds of compressed packet read-ahead before decode, capped
  at 8 MiB of packet payload/side data and 2048 packets, plus one in-flight packet.
  A dedicated producer owns `av_read_frame`; decoding and audio-track metadata
  use a snapshot of stream parameters, time bases, frame rates and languages.
  Initial reads wait for the target, a capacity limit or input termination, so
  short streams also drain. Subsequent reads consume while the producer refills.
  DTS measures the queued video span; byte/count caps bound missing or invalid
  timestamps. Cancellation wakes queue waits and interrupts IO; close joins the
  producer before freeing demux/decoder resources. Mac defaults to no read-ahead.
  This reserve absorbs brief delivery gaps, not sustained throughput deficits;
  it adds tuning/live latency and retains no DVR history. Queue seconds/bytes
  appear in diagnostics separately from renderer queues.
- `AVSampleBufferRenderSynchronizer` paces video and audio on one media clock.
  The worker waits for renderer readiness and limits decode-ahead to 600 ms.
  Startup waits for at least 150 ms of audio and 100 ms of video (video alone
  for audio-free input). Pause stops that clock and naturally bounds buffering. After a pause of at
  least 15 seconds, resume reconnects to the current live stream. No DVR is kept.
  Cmd-I shows queue depth and observed audio starvation transitions; these are
  media-time observations, not hardware underrun counts. Generation checks
  discard retired-session callbacks. Stop cancels network IO and flushes output.
- FFmpeg logs are silenced, errors are fixed safe strings, and no media URL is
  exposed in diagnostics. For Plex HLS segments missing a token, the top-level
  token is appended only for the same scheme, host and effective port.

This is a hybrid GPU IDCT decoder, not dedicated MPEG-2 hardware decoding and
not an all-GPU implementation. Floating-point IDCT can differ from CPU integer
IDCT and that difference can propagate through predicted frames. No formal
MPEG-2/IEEE-1180 conformance or production reliability claim is made.

## Build and verification

`ci_scripts/install_cinerama_mpeg2.sh` downloads a checksum-pinned LGPL FFmpeg
source archive, applies `patch_ffmpeg.py`, builds a minimal static configuration,
retains a relinkable bridge object at `.build/metal-mpeg2/relink/Decoder.o`,
and links it into a versioned dynamic `CineramaMPEG2.framework` inside a generated
arm64 macOS xcframework. Sources, archives and frameworks remain git-ignored.
The app's normal signed build and Mac test scripts install/rebuild it as needed.
The TV builder calls the same recipe with `tvos` and `tvos-simulator`, producing
a separate `CineramaMPEG2TV.xcframework` containing only TV slices. The boundary
verifier rejects the Mac binary on TV. See [TV Live TV](../../docs/tvos-live-tv.md)
for TV controls, build/cache/relink paths and hardware acceptance.

```sh
./scripts/test_mpeg2_native.sh
CINERAMA_MACOS_SIGNING_IDENTITY='Apple Development: kenkenchu@gmail.com (BZ2K63HJTE)' ./scripts/build_macos.sh
CINERAMA_MACOS_SIGNING_IDENTITY='Apple Development: kenkenchu@gmail.com (BZ2K63HJTE)' ./scripts/test_macos.sh
```

Native input-buffer regressions compare serial/buffered pixels, timestamps and
sample counts, exercise short EOF and cancellation while full, and compare paced
HTTP delivery with/without read-ahead across an injected one-second gap.

Native tests generate their own three-second MPEG-2/AC3 fixtures, including
progressive, TFF/BFF interlaced, 4:2:2, 1920x1080 interlaced and HLS. Each
has I/P/B frames. Both decoders must return 90 progressive frames or 180
deinterlaced field outputs, matching timestamps, cadence and audio counts. PCM
timestamps and aggregate durations must be contiguous. GPU block counts prove real execution; every Y/Cb/Cr output sample is
compared against CPU output. The test also checks missing-input failure and
cancellation. A loopback HTTP server publishes a growing HLS playlist and
requires a synthetic token on both playlist and segment requests, exercising
reloads and same-origin authentication propagation. Metal API validation is on.
Tests launch no player UI, browser, real Plex session or external network stream.

Initial local results on Apple M5: all six cases passed, PSNR 65.8–66.4 dB and
maximum sample error 2. One representative three-second HD run took 0.159 s
with CPU decoding and 1.644 s in Metal mode (including decode and output sample
creation, excluding display pacing; Metal validation enabled). GPU execution
was only 0.070 s; synchronous row submission, waits and copies dominate. These
numbers demonstrate real-time headroom for that fixture but **not a speedup**.
They are not measurements of the user's live channel, CPU savings or energy.

Both signed platform builds, 180 hosted Mac tests and 32 tvOS 26 simulator tests
passed during integration. For resumable milestones and current evidence see
[the implementation plan](../../docs/live-tv-pipeline-plan.md).
User verification of picture, audio synchronization,
Plex-server delivery and controls remains pending; agents do not manually launch
the app. Future optimization should batch more work without violating first-field
reference dependencies, then measure production live streams without validation.

## Source and licensing

FFmpeg: https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz

SHA-256: `05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41`.
GPL/nonfree/autodetected third-party components are disabled. FFmpeg copyright
and LGPL text are retained in its fetched source and in the app's third-party
notices. `patch_ffmpeg.py`, the bridge source and the exact compile/link recipe
are committed. A recipient can rebuild or replace the dynamic framework.
A distributable build must accompany the corresponding FFmpeg source and
relinkable bridge object, as applicable to LGPL section 6; the repository alone
is not a prepackaged binary distribution kit. The existing app license and
original-project notices remain unchanged.

## Audio tracks checkpoint (M2)

The native demuxer enumerates audio stream IDs, languages, codecs and channel
counts. Both platform players expose supported selections; the Mac player retains its existing
language preference/metadata matching. Selection is an atomic request consumed
on the decoder worker, which replaces only the audio context and converter.
The UI flushes old PCM and rejects stale samples tagged with the retired stream
ID. Video and the common clock stay running. Brief switch gaps and default-output
device changes still need user verification. M4 listens for automatic output
flush/configuration changes and requests bounded recovery.
The system audio renderer follows its default output; decoded channel count in
Cmd-I is not proof of physical multichannel speaker output.

Native fixtures additionally cover 5.1 AC3 and a two-language AC3/AAC stream.
Checks assert PCM channel descriptions and sample rate, switch from 5.1/48 kHz to
stereo/44.1 kHz and back, and reject non-audio stream IDs. Live TV captions and DVR are explicitly out of scope.

## Recovery checkpoint (M4)

The worker retries recoverable opens/reads, corrupt-packet decode failures and
resolution changes using the same session URL and decoder mode. Delays are 0.5,
1 and 2 seconds; 30 seconds of decoded progress resets the consecutive budget.
Native error strings stay safe and credential-free. Permanent unsupported-format
and Metal errors do not silently fall back to CPU. Renderer automatic flush and
configuration notifications request the same serialized reconnect path.

The output clock reanchors across timestamp discontinuities and reconnects while
elapsed session time and the selected audio signature are retained. Rendering and
decode-ahead waits have an eight-second running-playback watchdog. Explicit stop
cancels the worker/input and invalidates callbacks. No background recording is
created; long-pause resume refreshes the existing live session.

Verification includes HTTP 503 classification, cancellation during a blocked HTTP
open, resolution-change classification and deterministic retry/clock-policy tests.
These are not substitutes for real-channel interruption, output-device, wake,
rapid retune and audio/video synchronization checks. Sustained validation is M5.
See the [plan](../../docs/live-tv-pipeline-plan.md) for current progress and pending acceptance checks.

## Sustained validation checkpoint (M5)

Cmd-I includes output dimensions and observed timestamp cadence, submitted/late
video counts, audio/video queue starvation transitions, sampled peak queue depth
and queue-end A−V offset. Submission counts span recovery; queue statistics reset
with each decoder/output context. Late submission is not a measured display drop;
queue-end offset is not measured speaker/display synchronization or clock drift.
No media URLs, token values or track titles are added to diagnostics.

Run the regular native checks plus a continuous HD interlaced decode in each mode:

```sh
CINERAMA_MPEG2_SOAK_SECONDS=60 ./scripts/test_mpeg2_native.sh
```

The optional duration accepts 10–3600 seconds of generated media. Each mode uses
the same 1080i fixture, validates every output's 60 Hz cadence and contiguous PCM,
releases samples immediately and samples process RSS after 300 video outputs.
Peak RSS growth above that baseline must stay below 64 MiB. Metal validation
stays enabled; this is an unpaced decoder ownership regression, not a renderer,
network, live-latency, CPU/energy benchmark or proof of hours-long bounded memory.
The fidelity suite remains separate and retains short outputs for pixel comparison.

For user live comparisons, quit/reopen the signed app, select CPU, tune the same
channel, allow 30 seconds to settle, then record Cmd-I values and Activity Monitor
CPU/memory over a fixed five-minute interval. Repeat with Metal using the same
channel, window size, audio track and output device; repeat CPU afterward to expose
broadcast/content variation. Record motion quality, audible drift, overload warnings
and any recovery. Test short pause and >15-second pause separately. Standard remains
the rollback route. Sequential live samples cannot establish identical content or
energy savings. Longer renderer/network, sleep/wake and physical-output validation
remain pending and user-owned; no caption or DVR verification is required.

The hosted Mac suite additionally exercises the actual engine worker and
AVFoundation renderers in CPU/Metal modes without opening a window. Run
`scripts/test_macos.sh`; it prepares a cached 60-second 1080i/AC3 fixture using
`test_mpeg2_native.sh --prepare-renderer-fixture`. Coverage includes paced
progress, short and 16-second pauses, bounded paused video submission, reconnect,
rapid reload and stop during retry. Startup uses 150 ms audio because the hosted
renderer backpressured at 192 ms, preventing the former 200 ms threshold from
starting its clock. This is lifecycle coverage, not physical output or sustained
renderer/network memory/energy acceptance.
