# Experimental tvOS Live TV

The TV **Live TV** tab ports the Mac CPU/Metal MPEG-2 experiment to Apple TV HD
on tvOS 26+. It defaults to **Disabled**. Choose **Experimental CPU** or
**Experimental Metal**, then select a channel. Decoder changes apply on the next
tune. There is no automatic CPU fallback or TV VLC route. Library playback keeps
its separate native AVKit player and existing format restrictions.

## Ownership and flow

- `TVLiveTVView` owns the remote-focused channel grid, search and decoder picker.
  The shared `LiveTVViewModel` loads the highest-priority connected server's
  provider/channels. No guide, program schedule or EPG is required.
- `TVLivePlayback` tunes once through the shared Plex API, rejects unconfirmed
  remux decisions and unsupported metadata, activates the TV playback audio
  session before the engine creates/attaches audio output, serializes
  server-scoped timeline reports and pings the remux session. Engine construction
  on channel selection must stay inactive so it cannot open audio output on the
  channel grid before presentation. Stopping an unused engine also stays inactive.
  Dismissal cancels playback and sends stopped/cleanup after queued reports.
  A tune completing after dismissal is cleaned up without starting a decoder.
  Profile changes cannot authorize a retired session to start or report.
- `MPEG2Pipeline.swift` owns the shared FFmpeg worker, sample-buffer renderers,
  common clock, bounded queues, audio switching, diagnostics and recovery.
  `ExperimentalMPEG2Engine.swift` retains the Mac protocol/AppKit adapter;
  `TVLivePlayerScreen` owns its UIKit display-layer host and TV controls.
- CPU parsing, motion compensation and BWDIF field-rate deinterlacing run in
  both modes. Metal offloads IDCT only. This is not hardware MPEG-2 decoding.
- TV metadata and actual native bitstream checks reject dimensions above
  1920 × 1080. No downscaling, server A/V re-encoding or UHD rescue is added.
  The native decoder also rejects other video codecs and unsupported formats.

Remote Play/Pause and the focused button control the shared clock. Back returns
to channels. The app-owned controls remain visible for this initial experiment.
Audio offers the decoder's supported tracks and marks the current one. The red
LIVE marker is status only. Playback Information exposes safe decoder, GPU,
format, queue and recovery facts, without credentials or stream URLs.

## Limits and recovery

No Live TV captions/subtitles, DVR, seeking, skip, Go Live, recording, HDR,
Atmos restoration or library-engine expansion. Short pauses retain bounded
queues; resuming after 15 seconds refreshes the existing live URL. Backgrounding
pauses playback, and foreground return does not automatically resume it.
Retryable failures use the shared three-attempt budget; permanent errors remain
visible. Select another mode and retune manually if necessary.

A8 real-time performance, field cadence at the display, physical speaker layout,
output synchronization, route changes, interruptions, wake, focus and sustained
memory/energy need device verification. Metal is not assumed faster than CPU.
Mac milestone M5/M6/M7 acceptance does not establish TV production readiness.

## Build and verification

`ci_scripts/install_cinerama_mpeg2_tvos.sh` creates separate arm64 device and
simulator slices in `Frameworks/CineramaMPEG2TV.xcframework`; the module/framework
inside remains `CineramaMPEG2`. It uses the same pinned LGPL FFmpeg source and
patch as Mac, with separate caches, SDKs and tvOS 26 minimums. Build/test scripts
bootstrap it automatically. Desktop VLC and CineramaDovi remain excluded.
The boundary gate checks source ownership and native slice platform/architecture.

The relinkable objects and static archives remain under
`.build/metal-mpeg2-tvos{,-simulator}/relink` and `install/lib`. Preserve these and
the corresponding FFmpeg source for distribution obligations. TV Settings →
About → Third-Party Notices includes the FFmpeg notice and LGPL text.

Run both signed builds, both hosted test suites and native MPEG-2 checks; see
[testing](testing.md) and [device workflow](tvos-prototype.md). TV tests generate
and bundle a local HD fixture into the test target only. CPU/Metal renderer
checks exercise playback, bounded pause, reconnect, rapid reload and stop
headlessly; policy tests cover copy-only gating, UHD/codec rejection and late
tune cleanup. They open no Plex tuner or player screen.

For user verification, open Live TV, select CPU and tune a known HD MPEG-2
channel. Check motion/audio, remote pause/resume, audio selection, Back and a
pause longer than 15 seconds. Repeat with Metal on the same channel. Check GPU
block counts in Playback Information (zero CPU, increasing Metal). Check Plex
Dashboard confirms copying. Report failures using mode/channel/codec and safe
diagnostics. No captions or DVR checks are required.

Verified 2026-10-26: both signed builds, 186 Mac tests, 39 tvOS 26.0 simulator
tests, native stream/fidelity/fault/cancellation checks, platform/slice boundaries
and documentation/diff checks pass. The signed TV app was installed without
launching it. The attempted Apple TV HD test launch was blocked by device sleep;
real-channel/user hardware acceptance is pending. Host audio initially stalled
renderer tests; separate runs passed after the user selected built-in speakers.

Startup correction (2026-10-27): the user reported both CPU and Metal freezing
on channel selection, before the player appeared. The shared engine previously
attached its audio renderer in its initializer, before TV audio-session activation;
the renderer tests used the reverse order. Output creation/attachment now waits
until `load`, after TV activates audio. The TV renderer regression constructs and
stops an inactive engine before activation, then exercises playback in both modes.
Real-channel Apple TV confirmation remains required; simulator playback does not
establish the hardware hang is resolved.

Verification: both signed builds, all 186 Mac tests (on rerun), all 39 TV tests
on both tvOS 26.0 simulator and Apple TV HD/tvOS 26.6, and native CPU/Metal
fidelity, stream, fault and cancellation checks pass. The first Mac run exited
unexpectedly during its renderer test (185 other tests passed); the full rerun
passed without further source changes. Device renderer tests use a generated
fixture and do not tune a Plex channel. The signed TV app was reinstalled for
user channel verification without a manual launch.
