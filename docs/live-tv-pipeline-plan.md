# Mac Live TV pipeline implementation plan

## Resume here

- Branch: `codex/metal-mpeg2-prototype`.
- Scope: production-quality HD SDR MPEG-2 Live TV on Mac, using the new FFmpeg
  pipeline; CPU and Metal IDCT remain comparable. Existing AVPlayer/VLC routes
  remain available. This is not a plan to replace library playback or tvOS.
- User correction: **DVR is not required**. No buffer seeking, recording, skip
  controls or Go Live implementation. Pause/resume is in scope; long pauses must
  not grow memory without bound or become an implicit recording feature.
- Current milestone: M1, audio/video baseline. Planning checkpoint complete;
  implementation not yet started.
- Next action: inspect current native PCM timing and interlaced output, implement
  deinterlacing with field-order/cadence tests and establish audio diagnostics.
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
| M1 — Picture and audio baseline | Proper progressive output from interlaced sources; field order/cadence; stable timestamped PCM; buffer/underrun diagnostics | Generated progressive/TFF/BFF fixtures; CPU/Metal fidelity and cadence checks; safe pause/resume; user picture/audio sync check | In progress |
| M2 — Audio tracks and surround | Enumerate streams; select tracks and honor language; preserve supported multichannel PCM and layout; output-device recovery | Multi-track and 5.1 fixtures; layout/timestamp/selection tests; user surround and device-switch checks | Planned |
| M3 — Captions and subtitles | Broadcast caption/subtitle extraction, selection and Off, synchronized display following macOS caption preferences | Reproducible caption fixtures, timing/selection tests; user style/readability checks; explicitly document unsupported formats | Planned |
| M4 — Live recovery and lifecycle | Stalls, HLS discontinuities, timestamp resets, damaged packets, format changes; rapid retunes, stop, sleep/wake and bounded long pauses | Deterministic network fault/cancellation tests; lifecycle/retired-session tests; user sustained channel/pause/wake checks | Planned |
| M5 — Diagnostics and sustained validation | Video drops, audio starvation, buffer depth, format/cadence, timing drift; bounded memory and repeatable comparisons | Long headless stream tests, safe diagnostics; repeatable user live comparisons with identical settings/content where possible | Planned |
| M6 — Metal efficiency | Reduce synchronous submission/waits and copies without violating reference/field dependencies; retain CPU oracle | Fidelity/conformance-oriented fixtures, benchmark without validation plus live CPU/energy measurements; no default change without evidence | Planned |
| M7 — Production acceptance | Resolve remaining supported-MPEG-2 gaps, simplify experimental controls, operational docs and dependency/relink artifacts | Full required builds/tests, explicit user picture/audio/caption/input acceptance; rollback to standard route retained | Planned |

DVR is excluded from all milestones. Seek/skip/Go Live stay disabled for this
pipeline. Other exclusions: library codec/container parity, HDR/Dolby Vision,
Atmos restoration, downloading, recording/scheduling, tvOS Live TV, and adding
EPG requirements. Supported subtitles and multichannel PCM are not a promise of
unimplemented library-engine parity.

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
