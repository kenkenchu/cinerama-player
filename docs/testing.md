# Automated Verification

Run automated tests after code changes. Both maintained schemes have hosted
unit-test targets. Test hosts may run as part of Xcode's test action; manual app
launches and visual inspection remain with the user. Run both suites for shared,
project or cross-platform changes, and the applicable suite for platform-only
behavior. Keep the separate signed-build gates in `development-workflow.md` and
`tvos-prototype.md`.

## Commands

Bootstrap with the signed build scripts first. Both test scripts regenerate
XcodeGen, enforce platform/test source boundaries and run `xcodebuild test`.
They require explicit signing settings and never fall back to ad hoc signing.

```bash
CINERAMA_MACOS_SIGNING_IDENTITY='Apple Development: kenkenchu@gmail.com (BZ2K63HJTE)' \
  ./scripts/test_macos.sh

CINERAMA_TVOS_TEAM=JCJFCBSNUG \
  CINERAMA_TVOS_DEVICE_ID=c8b3bc526b697182f0646a639aef4be26f1ca852 \
  ./scripts/test_tvos.sh
```

The TV script uses the connected, paired Apple TV HD and automatic development
provisioning. It installs/runs the app test host and `CineramaTVTests` bundle on
the device. Keep it awake and reachable. Discover the build destination again
if pairing changes; see [TV device workflow](tvos-prototype.md). No simulator
runtime or historical mobile/simulator helper is required. Do not silently skip
the suite if the TV is unavailable; report the execution blocker separately from
compile results.

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
executed on Apple TV HD. Both signed builds and source-boundary checks passed.
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
