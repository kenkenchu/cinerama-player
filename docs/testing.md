# Automated Verification

Run automated tests after code changes. Both maintained schemes have hosted
unit-test targets. Test hosts may run as part of Xcode's test action; manual app
launches and visual inspection remain with the user. Run both suites for shared,
project or cross-platform changes, and the applicable suite for platform-only
behavior. Keep the separate signed-build gates in `development-workflow.md` and
`tvos-prototype.md`.

## Commands

Bootstrap Mac dependencies with the signed Mac build script first; TV simulator
tests need Xcode, XcodeGen and the tvOS 26 runtime. Both test scripts regenerate
XcodeGen, enforce platform/test source boundaries and run `xcodebuild test`.
Physical-device/Mac tests require explicit signing settings and never fall back
to ad hoc signing. Simulator tests require neither signing nor a development team.

```bash
CINERAMA_MACOS_SIGNING_IDENTITY='Apple Development: kenkenchu@gmail.com (BZ2K63HJTE)' \
  ./scripts/test_macos.sh

# Local default: tvOS simulator, usable away from the Apple TV.
./scripts/test_tvos.sh

# Explicit physical-device run:
CINERAMA_TVOS_TEAM=JCJFCBSNUG \
  CINERAMA_TVOS_DEVICE_ID=c8b3bc526b697182f0646a639aef4be26f1ca852 \
  ./scripts/test_tvos.sh
```

Without `CINERAMA_TVOS_DEVICE_ID`, the TV script selects the newest available
**tvOS 26.x** runtime and creates/reuses a dedicated `Cinerama TV Tests` simulator at
1080p. It runs through CoreSimulator without opening the Simulator GUI. Set
`CINERAMA_TVOS_SIMULATOR_ID` to select an existing simulator explicitly. On a new
Mac, install a runtime first:

```bash
xcodebuild -downloadPlatform tvOS -buildVersion 26.0 -architectureVariant arm64
```

With `CINERAMA_TVOS_DEVICE_ID`, the same script uses the paired Apple TV HD and
automatic development provisioning. Keep it awake and reachable; rediscover the
build destination if pairing changes. See [TV device workflow](tvos-prototype.md).
Do not silently skip an explicitly requested device run when the TV is absent;
use the default simulator command for local automated work instead. Simulator
products use `.build/tvos-simulator/DerivedData`, separate from signed device
products in `.build/tvos/DerivedData`; never install simulator products on the TV.

The compatibility baseline is tvOS 26; an installed 27.x runtime never replaces
the required 26.x default. Newer runtime checks can be requested explicitly
with a simulator ID, in addition to the 26.x baseline. Simulator tests verify
logic and native lifecycle/delegate contracts; they do not emulate Apple TV HD's
A8 performance, tvOS 26.6 media decoding or hardware audio/display behavior.
The boundary verification script also enforces tvOS 26.0 deployment for the app
and hosted tests in every configuration.
Physical-device signed builds and periodic device test runs remain required.

Additional Xcode options can follow the script, for example
`-only-testing:CineramaTests/MacPlaybackWindowTests` for a focused Mac run. A
focused run is useful during implementation; it does not replace the applicable
full suite before finishing. Result bundles are written by Xcode under each
platform's `.build/.../DerivedData/Logs/Test` directory; keep them out of Git.

## Coverage and Ownership

| Area | Mac | TV |
| --- | --- | --- |
| Plex part decoding, library ordering and unwatched filters | Shared test source | Same source compiled against the TV module |
| Mac fullscreen state, host reparenting, retired-host safety | Window and AppKit attachment suites | Native TV presentation stays separate |
| Engine routing, remux/fallback, subtitle eligibility and HDR/Dolby Vision conversion | Mac playback/converter suites | TV resolver and copy-only gate suites |
| Apple TV HD resolution, HDR, codec and frame-rate restrictions | Independent Mac capability tests | TV rejection/direct/remux/track-selection cases |
| Profile/server/movie/series track preferences and explicit Off | Existing Mac preferences/selection tests | Isolated UserDefaults tests with semantic track matching |
| Playback cleanup and Back delegate | Mac window/recovery suites | Idempotent finish, terminal stopped state, foreground pause and native dismissal callback |

`CineramaTVTests` imports `CineramaTV`, not the Mac module. Only the explicit
shared test allowlist in `project.yml` and `verify_platform_boundaries.py`
compiles into both test targets. Add platform-independent test files to that
allowlist deliberately; do not include the entire Mac test tree in TV. Test
sources never compile into either shipping app target. TV preference tests use
injected, unique defaults suites and remove their persisted state afterward.

## Current Baseline

On 2026-10-25, all **178 Mac tests** and **32 TV tests** passed, with TV tests
executed on both Apple TV HD and the local tvOS 26.0 (23J352) arm64 simulator. Both signed builds and source-boundary checks passed.
Parameterized cases exercise additional input combinations within those tests.

Enabling the full Mac baseline also made empty-RPU rejection deterministic
before the C ABI, made the UHD numeric assertion explicit, and separated the
unsupported 10-bit H.264 routing expectation from HDR enhancement tests. The TV
lifecycle tests exposed and fixed attempts to restart an already stopped session.

These are unit and native attachment/delegate tests, not visual or media-output
audits. Actual focus traversal/restoration, picture/audio output, system caption
appearance, hardware codec fidelity and sustained A8 performance still require
user device checks. Full Plex timeline/remux networking races and end-to-end
caption rendering are not yet comprehensively covered by automated tests.

## Native MPEG-2 CPU/Metal Experiment

Run `scripts/test_mpeg2_native.sh` after changes to `Native/CineramaMPEG2` or its
FFmpeg patch/build. It generates MPEG-2/AC3 fixtures and compares CPU and real GPU
output for progressive, interlaced, 4:2:2, HD and local/HTTP HLS, including growing
playlists and token propagation. It runs headlessly with Metal validation and
checks cancellation, timestamps, audio counts and GPU execution. See the
[experiment README](../Native/CineramaMPEG2/README.md) for fidelity thresholds,
measured limits and licensing/build details. It does not open Plex or establish
real-channel audio/video synchronization or energy savings. The original block
kernel tests remain available through `swift test --package-path
Native/MetalMPEG2Prototype -c release`.

Integration checkpoint: 180 Mac tests and 32 tvOS 26 simulator tests passed with
both signed builds. The experimental decoder now also has an explicit TV port; project changes
require both platform verification gates. See [TV Live TV](tvos-live-tv.md).

M1 pipeline checkpoint: field-rate deinterlacing now adds a BFF fixture and checks
90 progressive versus 180 interlaced outputs, output cadence and contiguous PCM
timing. Buffer startup/starvation state adds two hosted tests (182 Mac total).
See [the resumable plan](live-tv-pipeline-plan.md) for evidence and pending user
checks; DVR is excluded.

M4 pipeline checkpoint: 184 Mac tests pass. Native fault cases classify HTTP 503
and resolution changes as recoverable and cancel an in-flight blocked HTTP open
within two seconds. Hosted policy tests bound retries and check timestamp and
long-pause thresholds. Full render-loop recovery, output devices, wake and
long-duration memory/energy remain user/runtime validation gates; see the
[milestone plan](live-tv-pipeline-plan.md). No DVR or caption work is in
scope. Mac-only changes retain the last signed TV/32-test baseline.

M5 initial checkpoint: signed Mac build and 185 Mac tests pass. Optional
`CINERAMA_MPEG2_SOAK_SECONDS=60 ./scripts/test_mpeg2_native.sh` adds continuous
1080i CPU/Metal decoding, field cadence, PCM continuity and post-warmup sampled
RSS growth checks without retaining frames. Both modes returned 3,600 video
outputs/1,875 PCM buffers; sampled growth was 0.06/0.00 MiB. This unpaced native
check does not exercise renderer queues or establish live-player memory,
synchronization or energy performance. See the native README and milestone plan
for limits and the repeatable user comparison procedure. TV inputs are unchanged.

M5 renderer checkpoint: `test_macos.sh` now prepares a cached generated 60-second
1080i/AC3 fixture before Xcode tests. When invoking Xcode directly, first run
`scripts/test_mpeg2_native.sh --prepare-renderer-fixture`. The hosted CPU/Metal
integration test uses the production worker/renderers headlessly to exercise
startup, short/16-second pauses, bounded paused submission, reconnect, sustained
paced progress, rapid reload and stop during retry. It found and guards against
startup waiting for 200 ms when audio backpressures at 192 ms; startup now needs
150 ms audio plus 100 ms video. This test does not audit speaker/display output,
long-duration renderer RSS, real network delivery or energy performance.

Verification on 2026-10-26: signed Mac build and 186 Mac tests passed, including
both renderer integration modes (74.4 seconds combined). Native cases/faults and
120-second CPU/Metal decoder soaks passed with validation; sampled RSS growth was
0.14/0.05 MiB. TV inputs and the prior signed TV/32-test baseline are unchanged.

## TV CPU/Metal port checkpoint (2026-10-26)

Both signed builds and the source/native-slice boundary checks pass. The Mac
suite passes **186 tests**; the tvOS 26.0 simulator suite passes **39 tests**.
The new TV tests cover copy-only decision gating, stream/metadata HD/SDR limits,
stop idempotence, cancelled late-tune cleanup and retained pause intent. Native
TV framework tests compare CPU/Metal NV12 samples, check field cadence and PCM
format/counts, and require real GPU blocks in Metal mode. Paced TV renderer
checks cover startup, bounded pause, resume, reconnect, rapid reload and retired
worker safety in both modes. They use a generated fixture bundled only with
the test target, not a Plex channel or tuner. Native Mac stream/fidelity/fault/
cancellation checks also pass after the shared builder/decoder changes.

Initial concurrent Mac/simulator renderer attempts stalled inside host audio
output initialization; the Mac test then timed out. The user switched macOS
output to built-in speakers, after which separate full Mac and simulator runs
passed. This is not evidence of a pipeline synchronization fix or a conclusive
diagnosis of the previous output-device failure.

The signed TV app was installed without manual launch. An additional automated
Apple TV HD test run was attempted but could not launch because the device was
asleep. No device test pass is claimed. User live-channel picture/audio/focus
and sustained A8 performance/energy remain pending, as do physical audio route
and output synchronization checks. Mac M5/M6/M7 acceptance remains separate.

## TV compressed input buffering (2026-10-28)

Both signed builds, 187 Mac tests and 40 TV tests pass on the tvOS 26.0 simulator
and Apple TV Lite. TV renderer tests now use the production two-second input
reserve and assert bounded compressed depth/bytes while paused, followed by
resume, reconnect, rapid reload and stop. Native tests compare buffered/serial
video bytes, timestamps and sample counts, short-input EOF, buffered audio
switching, full-queue cancellation and cancellation during stalled HTTP input.
A paced HTTP control sees a 604 ms sample wait across an injected one-second
network gap; buffered consumption sees 7 ms. Existing CPU/Metal fidelity, HLS,
format-fault and IO-cancellation tests pass. See [TV Live TV](tvos-live-tv.md)
for limits. These checks do not establish real Plex-channel delivery, sustained
A8 performance, physical A/V output or long-term memory/energy behavior.
