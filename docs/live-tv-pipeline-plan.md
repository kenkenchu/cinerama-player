# Mac Live TV pipeline implementation plan

## Resume here

- Branch: `codex/metal-mpeg2-prototype`.
- Scope: production-quality HD SDR MPEG-2 Live TV on Mac, using the new FFmpeg
  pipeline; CPU and Metal IDCT remain comparable. Existing AVPlayer/VLC routes
  remain available. This is not a plan to replace library playback or tvOS.
- User corrections: **DVR and Live TV captions/subtitles are not required**.
  No caption extraction/rendering/selection or caption-style work in this plan.
  No buffer seeking, recording, skip controls or Go Live implementation.
  Pause/resume is in scope; long pauses must not grow memory without bound or
  become an implicit recording feature.
- Work status: **paused at the user's request after the M4 implementation
  checkpoint**. M1, M2 and M4 have automated verification; user runtime gates
  remain pending. Do not resume implementation until the user requests it.
- Latest completed code checkpoint: M4 bounded recovery and lifecycle (P4 below).
  M2 code is `e315432`; caption scope correction is `40178e4`.
- Next action on resume: review P4 limitations and user feedback, then M5
  sustained validation/diagnostics. M6 Metal optimization and M7 production
  acceptance remain planned. M3 is excluded. No DVR or caption work.
- Baseline commit: `f27faa6`. Both signed builds, 180 Mac tests, 32 tvOS 26 tests
  and six native stream cases passed at that checkpoint.

## Working rules

Complete small checkpoints on this branch. At every checkpoint update this file
with changes, verification results, remaining limitations, commit reference and
exact next action; commit and push after the applicable checks. Do not mark a
milestone fully verified until its required automated checks and user runtime
checks are distinguished and recorded. User-owned checks may remain pending
while independent implementation proceeds. Never manufacture runtime approval.

Read AGENTS.md and AGENTS.local.md first on resume, then this file, playback.md,
testing.md and Native/CineramaMPEG2/README.md. Check Git status and preserve
unrelated changes. No manual app launches or visual inspection by agents.
Automated native/hosted tests are authorized. Use the installed Apple Development
identity for signed Mac builds. Shared/project changes require both signed builds
and both suites; Mac-only implementation requires signed Mac build, Mac tests
and affected native tests. Do not expose tokens or media URLs in diagnostics.

Plex continues to own tuning, server identity, copy-only decisions, keepalives
and session cleanup. No server audio/video re-encoding. Keep the experiment
opt-in until the final acceptance gate; do not hide CPU fallback during A/B tests.

## Milestones and acceptance gates

| Milestone | Deliverables | Acceptance | Status |
| --- | --- | --- | --- |
| M0 — Plan and baseline | Resumable plan, exclusions, previous evidence | Linked from docs index; clean diff and links | Complete |
| M1 — Picture and audio baseline | Proper progressive output from interlaced sources; field order/cadence; stable timestamped PCM; buffer/underrun diagnostics | Generated progressive/TFF/BFF fixtures; CPU/Metal fidelity and cadence checks; safe pause/resume; user picture/audio sync check | Implemented; user verification pending |
| M2 — Audio tracks and surround | Enumerate streams; select tracks and honor language; preserve supported multichannel PCM and layout; output-device recovery | Multi-track and 5.1 fixtures; layout/timestamp/selection tests; user surround and device-switch checks | Tracks/layout implemented; device recovery/verification pending |
| M3 — Captions and subtitles | Removed at the user's request | No Live TV caption implementation or acceptance gate | Out of scope |
| M4 — Live recovery and lifecycle | Stalls, HLS discontinuities, timestamp resets, damaged packets, format changes; rapid retunes, stop, sleep/wake and bounded long pauses | Deterministic network fault/cancellation tests; lifecycle/retired-session tests; user sustained channel/pause/wake checks | Implementation checkpoint complete; runtime gates pending |
| M5 — Diagnostics and sustained validation | Video drops, audio starvation, buffer depth, format/cadence, timing drift; bounded memory and repeatable comparisons | Long headless stream tests, safe diagnostics; repeatable user live comparisons with identical settings/content where possible | Planned |
| M6 — Metal efficiency | Reduce synchronous submission/waits and copies without violating reference/field dependencies; retain CPU oracle | Fidelity/conformance-oriented fixtures, benchmark without validation plus live CPU/energy measurements; no default change without evidence | Planned |
| M7 — Production acceptance | Resolve remaining supported-MPEG-2 gaps, simplify experimental controls, operational docs and dependency/relink artifacts | Full required builds/tests, explicit user picture/audio/input acceptance; rollback to standard route retained | Planned |

DVR and Live TV captions/subtitles are excluded from all milestones. Seek/skip/Go Live stay disabled for this
pipeline. Other exclusions: library codec/container parity, HDR/Dolby Vision,
Atmos restoration, downloading, recording/scheduling, tvOS Live TV, and adding
EPG requirements. Multichannel PCM is not a promise of unimplemented library-engine parity.
Library subtitle support remains on the existing standard playback routes.

## Existing architecture and evidence

`ExperimentalMPEG2Engine.swift` owns the Mac sample renderers, shared audio/video
clock, worker lifecycle and diagnostics. `Native/CineramaMPEG2/Decoder.mm` owns
FFmpeg demux/decoding, PCM/NV12 sample creation and batched Metal IDCT. The FFmpeg
patch changes IDCT callbacks only; motion prediction and parsing remain CPU work.
The coordinator passes the already-authorized copy-only tuned session. Settings
select Standard, Experimental CPU or Experimental Metal on the next tune.

Existing limits: stereo/default audio, no captions or track selection, woven
interlace, explicit failure instead of recovery. Automated fixtures decode 90
I/P/B frames and audio for progressive, interlaced, 4:2:2, HD, local HLS and a
same-origin token-protected growing HTTP playlist. Maximum observed CPU/Metal
pixel difference was 2, with PSNR approximately 66 dB; this is not formal MPEG-2
or IEEE-1180 certification.

User ran real Live TV in both modes. Read-only 30-second process measurements:
Experimental Metal 28.6% CPU; Experimental CPU 21.7%. Stack samples confirmed GPU
IDCT/waits versus CPU IDCT respectively. Earlier VLC reading was 51.9%, measured
by a different sampling method and on the previous pipeline. These sequential
samples are not controlled benchmarks or energy measurements. Metal's sample
had Core Audio overload warnings; the cause has not been isolated. Do not claim
that the user confirmed synchronization, picture fidelity or caption behavior.

## Verification commands

```sh
security find-identity -v -p codesigning
./scripts/test_mpeg2_native.sh
CINERAMA_MACOS_SIGNING_IDENTITY='Apple Development: kenkenchu@gmail.com (BZ2K63HJTE)' ./scripts/build_macos.sh
CINERAMA_MACOS_SIGNING_IDENTITY='Apple Development: kenkenchu@gmail.com (BZ2K63HJTE)' ./scripts/test_macos.sh
# Required additionally for shared/project changes:
CINERAMA_TVOS_TEAM=JCJFCBSNUG CINERAMA_TVOS_DEVICE_ID=c8b3bc526b697182f0646a639aef4be26f1ca852 ./scripts/build_tvos.sh
./scripts/test_tvos.sh
```

## Checkpoint log

### P0 — 2026-10-25: plan recorded

Created this plan and linked it from the docs index. DVR removed at the user's
explicit request. No implementation change in this checkpoint. Baseline and
known limitations above reflect source and previous verification, not new tests.
Verification: documentation references and diff checks. Commit: this planning
commit (find with `git log -- docs/live-tv-pipeline-plan.md`). Next: M1 discovery
and first tested audio/video change; record the result below before committing.

### P1 — 2026-10-25: M1 audio/video baseline implementation

Replaced woven output with LGPL FFmpeg BWDIF (`send_field`, automatic parity,
interlaced-only). Progressive sources pass through, while TFF/BFF interlaced
sources emit two progressive outputs per decoded frame. Added a bounded two-thread
filter graph; CPU and Metal modes use the same deinterlacer. Resolution/pixel-format
changes currently fail explicitly rather than reconfiguring (M4).

Startup now holds the shared clock until it has at least 200 ms of audio and
100 ms of video, or video alone for audio-free input. Added tested media-time
queue coverage and audio starvation transition observations to Cmd-I. These are
not hardware underrun measurements; the previous Core Audio warning cause is
not yet proven. Retired flush completions remain guarded. DVR remains excluded.

Verification: seven generated native cases passed with Metal validation,
including TFF/BFF, HD interlaced, 4:2:2 and growing authenticated HTTP HLS.
Interlaced cases returned 180 outputs at 60 Hz from 90 input pictures; progressive
cases retained 90 at 30 Hz. PCM durations/timestamps are contiguous. CPU/Metal
fidelity gates passed. Signed Mac and TV builds passed; 182 Mac tests and 32
TV tests passed. Source/project membership regenerated and boundary-checked.
User checks pending: motion quality/field order, initial startup and audio sync,
short pause/resume, and whether overload warnings recur on the real channel.
No agent visual inspection or app launch was performed.

Commit: the M1 checkpoint (find with `git log -- docs/live-tv-pipeline-plan.md`).
Next: M2 multichannel and audio selection; retain M1 user checks as pending.

### P2 — 2026-10-25: M2 audio selection and PCM layout checkpoint

M1 code checkpoint is `35193ca`. Added audio stream enumeration with stable
container IDs, language/codec/channel metadata and decoder availability. The
existing player language selection can use those tracks. Audio-only selection
capability is separate from caption selection, which remains disabled. Selection
is applied on the native worker; old-context output is flushed and stale tagged
samples are rejected in the Mac engine without retuning Plex or changing video.

Float PCM now preserves source sample rate and supported mono-to-7.1 channel
layouts with explicit Core Audio channel descriptions, instead of downmixing all
input to stereo/48 kHz. Unmapped layouts and unavailable codecs fail explicitly.
Default-output-device routing is delegated to AVSampleBufferAudioRenderer; actual
route changes, speaker mapping and output failure recovery remain unverified.
Robust failure recovery is carried into M4, not declared complete here.

Verification: nine native cases passed with real GPU execution and Metal
validation, including new 5.1 and English/Spanish multi-track fixtures. Checks
assert PCM channel count, explicit mapping and rate; switch 5.1/48 kHz → stereo
AAC/44.1 kHz → 5.1/48 kHz; reject invalid non-audio IDs. Deinterlaced CPU/Metal
outputs still pass PSNR >45 dB / maximum-error <=12 gates (edge interpolation can
amplify the earlier pre-deinterlace differences). Signed Mac build and 182 Mac
tests passed. M2 changes are Mac-only and add no project/shared/TV sources;
M1's signed TV build and 32-test tvOS 26 baseline are unchanged.

User checks pending: both language selections, switch gap and synchronization,
physical surround layout, headphones/default-output changes, plus M1 checks.
Commit: this M2 checkpoint (find with `git log -- docs/live-tv-pipeline-plan.md`).
Next (superseded by user scope correction below): M4 live recovery and lifecycle.

### Scope correction — 2026-10-25: Live TV captions removed

User explicitly stated Live TV does not need captions. M3 is out of scope, not
an unfinished parity requirement. No caption code or dependency was added.
Skip directly to M4. Live TV caption/seek controls should not advertise these
excluded capabilities. Existing library subtitle behavior remains unchanged.

### P4 — 2026-10-25: M4 implementation checkpoint; pause requested

Implemented bounded recovery in the existing engine worker. Retryable network,
packet-decode and video-format failures reopen the same authorized session URL
in the same CPU/Metal mode; no Plex retune/start/encoding request or silent CPU
fallback is added. Consecutive delays are 0.5, 1 and 2 seconds, then a safe visible
error. Thirty seconds of decoded progress replenishes the budget; a few packets
do not. Unavailable codecs and Metal failures remain explicit permanent errors.

Renderer automatic-flush/output-configuration notifications request the same
serialized recovery. Audio selection is restored by language/codec/channel
signature, old output is flushed, startup buffers refill, and the common clock
reanchors while elapsed session time is retained. Timestamp steps backward over
0.5 seconds or forward over 2 seconds flush/reanchor the output; starvation or
renderer backpressure exceeding eight seconds requests bounded reconnect.
Generation and flush IDs discard retired-session callbacks. Stopped engines
cannot be restarted by Play/Pause/recovery callbacks.

Pause keeps buffers bounded. Resuming after 15 seconds or more requests a fresh
read of the live session rather than retaining a DVR window. Foreground recovery
uses the coordinator's existing scene-active callback; no separate app launch or
manual device interaction was performed. Diagnostics expose reconnect and
timestamp-reset counts. GPU counters describe the current native decoder context
and may reset on reconnect.

Verification: signed Mac build passed; **184 Mac tests** passed. Nine native
stream cases and new fault checks passed with Metal validation: HTTP 503 is
classified recoverable, cancellation interrupts an in-flight blocked HTTP open
within two seconds, and concatenated streams changing resolution fail with a
recoverable classification. Policy tests cover the three-attempt limit, sustained
progress reset, discontinuity thresholds, long-pause threshold and non-resurrection
after stop. Existing field cadence, PCM layout/rate, audio switching, HLS token
propagation and CPU/Metal fidelity checks still pass. No project/shared/TV source
changes in M4; M1's signed TV build and 32 tvOS 26 tests remain the TV baseline.

Remaining acceptance/risk: native tests exercise failure signals and cancellation;
they do not prove the full render-loop recovery on a real Plex channel. User
verification is still required for repeated retunes, real network interruption,
short/long pauses, sleep/wake, output-device changes and synchronization. The
renderer may not recover from every terminal output failure; bounded retries
then show an error and retain Standard playback as the manual escape route.
Resolution changes recover by reopening at the live stream rather than seamlessly
continuing the old decoder. Corrupt-packet handling relies on FFmpeg and bounded
reconnects; exhaustive damaged-broadcast coverage and sustained memory/energy
validation belong to M5. No caption or DVR work is pending.

Commit: this M4 checkpoint (find with `git log -- docs/live-tv-pipeline-plan.md`).
**Paused here at the user's explicit request.** On resume, read this file and
AGENTS instructions, inspect Git status, incorporate user runtime feedback, then
start M5. Do not silently promote the experiment or enable Metal by default.
