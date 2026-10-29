# Experimental tvOS Live TV

The TV **Live TV** tab uses the CPU MPEG-2 decoder on Apple TV HD/tvOS 26+.
Channels load immediately; select a channel to start playback. The old decoder
preference is ignored. Metal playback is no
longer offered on TV after the user reported severe delays on Apple TV HD; Mac
CPU/Metal options remain independent. Library playback keeps its separate native
AVKit player and existing format restrictions.

## Ownership and flow

- `TVLiveTVView` owns the remote-focused channel grid, aspect-fit logos, search
  empty states and direct channel selection.
  The shared `LiveTVViewModel` loads the highest-priority connected server's
  provider/channels. No guide, program schedule or EPG is required. Its cover
  item (`TVLivePlayerPresentation`) captures provider, channel, server and player
  together; cover content must not depend on a second optional view-state value.
  Separate state can supply an empty cover on the first selection, blocking grid
  focus while leaving the channel grid visible.
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
- TV requests a two-second compressed input reserve before decoding, bounded to
  8 MiB / 2048 packets plus one in-flight packet. Read-ahead runs independently of
  renderer backpressure, so short network/segment delivery gaps can be absorbed
  without retaining seconds of decoded HD frames. Startup waits for the reserve
  or a capacity/EOF limit. Renderer startup remains 150 ms audio / 100 ms video;
  raising the audio renderer threshold can deadlock against its backpressure.
  Playback Information shows compressed input seconds/bytes separately from
  audio/video renderer queues. The reserve adds tuning/live latency; it cannot
  compensate for sustained slow delivery, slow decoding or gaps beyond the
  available reserve. Mac keeps its existing zero-read-ahead default.
- CPU parsing, IDCT, motion compensation and BWDIF field-rate deinterlacing
  handle video locally. This is not hardware MPEG-2 decoding.
- TV metadata and actual native bitstream checks reject dimensions above
  1920 × 1080. No downscaling, server A/V re-encoding or UHD rescue is added.
  The native decoder also rejects other video codecs and unsupported formats.

Remote Play/Pause and the focused button control the shared clock. Back returns
to channels. The compact app-owned controls hide after five seconds of active playback.
Remote direction or Select reveals them; pause, tuning, errors and VoiceOver
keep them visible. The full-screen Select target uses a custom undecorated
button style; do not
replace it with the system plain style, which can draw a bright focus plate over
the video when the controls hide. Audio opens a native track sheet; More holds Playback
Information and Back to Channels. Remote Back still returns directly to channels.
Audio offers the decoder's supported tracks and marks the current one. The red
LIVE marker is status only. Playback Information exposes safe decoder, GPU,
format, queue and recovery facts, without credentials or stream URLs.

## Limits and recovery

No Live TV captions/subtitles, DVR, seeking, skip, Go Live, recording, HDR,
Atmos restoration or library-engine expansion. Short pauses retain bounded
queues; resuming after 15 seconds refreshes the existing live URL. Backgrounding
pauses playback, and foreground return does not automatically resume it.
Retryable failures use the shared three-attempt budget; permanent errors remain
visible. Return to channels and retune manually if necessary.

A8 real-time performance, field cadence at the display, physical speaker layout,
output synchronization, route changes, interruptions, wake, focus and sustained
memory/energy need device verification beyond the confirmed basic CPU playback.
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
and bundle a local HD fixture into the test target only. CPU renderer
checks exercise playback, bounded pause, reconnect, rapid reload and stop
headlessly; policy tests cover copy-only gating, UHD/codec rejection and late
tune cleanup. A native presentation regression opens and dismisses the player
cover without connecting to a Plex tuner.

For user verification, open Live TV and tune a known HD MPEG-2
channel. Check motion/audio, remote pause/resume, audio selection, Back and a
pause longer than 15 seconds. GPU block counts should remain zero. Check Plex
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

Follow-up (2026-10-27): the user confirmed the audio-order change did **not**
resolve either mode's channel-grid freeze. Live TV's cover previously used the
channel as its item and conditionally read a separate optional playback state.
It now uses one complete presentation value, matching the library player flow,
with the provider/server snapshot retained through dismissal. The cover always
contains its player. A hosted native presentation regression opens the actual
Live TV cover, waits for its tune task, and dismisses it in both modes, without
connecting to Plex. User real-channel acceptance remains pending.

Follow-up verification: both signed builds and all **40 TV tests** pass on the
tvOS 26.0 simulator and Apple TV HD/tvOS 26.6. The new cover test passes in both
modes on the device, including first presentation, tune-task entry and dismissal.
The signed app was reinstalled without manual launch. Mac UI/shared decoder
sources are unchanged in this follow-up; the preceding 186-test Mac baseline
remains the latest run. Actual Plex-channel playback still needs user confirmation.

CPU-only checkpoint (2026-10-27): the user confirmed basic live-channel playback
works in both modes after the presentation fix, but Metal suffers severe delays
on Apple TV HD. At the user's request, TV now constructs only CPU sessions and
loads channels immediately with no enable/disable toggle or decoder picker.
The old decoder preference is ignored, so previous CPU, Metal and Disabled
selections all use CPU playback.
TV hosted renderer, native sample and presentation tests now exercise CPU only;
shared native Metal implementation and Mac behavior remain unchanged. This user
confirmation supersedes the pending basic-playback acceptance statements above;
long-duration, audio-route and comprehensive remote/focus checks remain pending.

CPU-only verification: both signed builds and all 40 TV tests pass on the tvOS
26.0 simulator and Apple TV HD/tvOS 26.6, including CPU renderer lifecycle,
native cadence/PCM and cover presentation/dismissal. The signed app was installed
without manual launch. Mac source and the preceding 186-test baseline are unchanged.

Focus-overlay correction (2026-10-28): the user reported a white mask covering
most of the picture a few seconds after tuning on Apple TV Lite. That timing
matches auto-hide handing focus to the full-screen Select button. Its style now
returns only the transparent label, bypassing system button decoration. Both
signed builds and all 40 tests on the tvOS 26.0 simulator pass. The signed app
was installed on Lite without manual launch. The user confirmed the mask is gone
on Lite. This confirms mask removal; automated tests do not establish broader
visual correctness.

Input-buffer checkpoint (2026-10-28): after the mask fix, the user reported one
channel frequently freezing picture and sound together, then resuming on Lite.
TV now enables the bounded compressed reserve above. Both signed builds,
187 Mac tests, and all 40 TV tests on the tvOS 26.0 simulator and Apple TV Lite
pass. Native CPU/Metal fidelity, stream/fault checks and new buffered tests pass:
exact video output/PTS and A/V sample counts, short EOF, audio switching, bounded
pause, cancellation on a full queue and during blocked HTTP IO. With a paced
one-second HTTP delivery gap, the serial control's longest sample wait was
604 ms versus 7 ms with buffering. This synthetic result does not establish
real-channel improvement. The signed app was installed on Lite without manual
launch; user verification on the affected channel is pending.
