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
both signed builds. The experimental decoder is Mac-only; project changes still
require both platform verification gates.

M1 pipeline checkpoint: field-rate deinterlacing now adds a BFF fixture and checks
90 progressive versus 180 interlaced outputs, output cadence and contiguous PCM
timing. Buffer startup/starvation state adds two hosted tests (182 Mac total).
See [the resumable plan](live-tv-pipeline-plan.md) for evidence and pending user
checks; DVR is excluded.
