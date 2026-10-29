# Cinerama — macOS and tvOS Agent Instructions

Cinerama, maintained in `kenkenchu/cinerama-player`, is an independent native
**macOS and tvOS** Plex client for the user's Apple silicon Mac and Apple TV HD.
Original-project credit is retained in README.md. Cinerama no longer tracks or
routinely synchronizes with the original project.
Read this file before planning, editing, committing, or pushing. Read
`AGENTS.local.md` immediately afterward if it exists. Then read
`docs/product-and-scope.md`, `docs/codebase-map.md`, and the relevant topic guide
from `docs/README.md` before discovery-heavy or deep implementation work.

## Platform and Ownership

- Maintained app schemes: `Cinerama-macOS` (Apple silicon, macOS 26+) and
  `Cinerama-tvOS` (Apple TV HD/A8, tvOS 26+, user device on 26.6).
  tvOS 26 remains the required compatibility baseline; do not raise the deployment
  target or require newer APIs without a tvOS 26 fallback. Feature availability
  differs; do not imply full TV/Mac parity.
- `project.yml` is the source of truth; XcodeGen produces `Cinerama.xcodeproj`.
- `App/` owns app lifetime and instrument-console navigation; `Features/Player/` owns the
  native player controls; `Playback/` owns AVPlayer and desktop VLCKit engines.
- Maintain native Mac behavior, keyboard/pointer interaction, resizable windows,
  fullscreen, and Local Network permission handling.
- Historical mobile targets, simulator helpers, TV extensions, and mobile VLC
  frameworks were removed. Maintaining tvOS does not authorize restoring
  those components in future development.
- `docs/upstream/` contains historical platform references, not active workflow
  requirements. Do not apply archived mobile verification or publishing steps.

## Product and Architecture

- Plex is the source of truth for metadata, watch state, libraries, and server
  identity. Persistence is limited to Keychain auth, UserDefaults preferences,
  documented caches, downloads, and pending offline sync.
- Views use `@Observable` view models; view models call `PlexService`. Use
  async/await. Keep Plex-specific code; no provider abstraction until a second
  backend is actually implemented.
- Connect every enabled server and keep failures per server. Rating keys are
  not globally unique: use `PlexItemID` (server ID + rating key).
- Playback starts direct, except for documented unsupported-format, remux, and
  local-download routes. Failed online direct play may fall back to Plex HLS.
  Server video/audio re-encoding is prohibited for all Cinerama playback, including
  Live TV, manual quality and audio rescue. HLS may start only after Plex confirms
  both tracks are copied; missing decisions fail closed. Remuxing is allowed.
- Mac engines conform to `PlaybackEngine`. Mac resolver decisions belong in
  `StreamResolver`; orchestration belongs in `PlaybackCoordinator`. TV uses
  `TVStreamResolver` and `TVPlaybackCoordinator` over shared Plex APIs until
  platform-neutral engine extraction is justified by actual reuse.
- Minimal dependencies: desktop VLCKit and CineramaDovi on Mac; native AVKit for TV libraries and CineramaMPEG2 CPU for TV Live TV.
  New Rust dependencies need
  notices in `Cinerama/Resources/ThirdPartyNotices.txt` and the native license list.
- Never log tokens or raw token-bearing media/artwork URLs.

## Style

`STYLE.md` is the Mac visual source of truth: native Mac controls, system materials
and Liquid Glass, a fixed Cinematic Metal Blue palette independent of system
appearance, no app-wide color tint. Sunset Coral is
reserved for the logo/icon. Follow its typography, spacing, and geometry rules.
TV interaction/layout rules live separately in `docs/tvos-ui.md`.

Visual changes apply to both macOS and tvOS by default. Carry the same palette,
materials and cinematic design language to both in the same checkpoint, adapting
for each platform's supported APIs, hardware and native input. Keep UI source
ownership separate; do not port Mac window transparency or pointer interaction
to fullscreen TV. Document platform-specific equivalents or unsupported effects,
and complete both signed builds for cross-platform visual updates. A user request
explicitly limited to one platform overrides this default.

## tvOS Target — Mac UI Protection

- Both platforms are maintained in this repository. Start with TV library
  playback, browsing, tracks and watch-state reliability; Live TV comes later.
  Follow `docs/tvos-design.md`, `docs/tvos-ui.md` and `docs/tvos-prototype.md`.
  Historical upstream TV code is reference material only.
- Give tvOS its own app shell, navigation, feature screens, styling, player
  controls and rendering hosts. Apple TV uses remote/focus interaction, not a
  touchscreen. Preserve existing Mac layouts and keyboard/pointer behavior.
- Enforce UI ownership through explicit XcodeGen source membership: neither
  target compiles the other platform's UI. Do not include all `Cinerama/Sources`
  indiscriminately in a new TV target or scatter TV branches through Mac views.
- Share platform-neutral Plex/data/session logic. Extract platform adapters
  where needed without changing Mac behavior; keep existing AppKit player hosts.
- Implement in small checkpoints and complete the signed Mac compile after code
  changes. A compile is not visual regression proof: Mac runtime checks require
  explicit user authorization before claiming visual/input parity.
- Preserve the prohibition on server A/V re-encoding on tvOS. Apple TV HD is the
  supported TV hardware. Reject 4K/UHD with an informational message and offer
  compatible HD versions; do not add software downscaling. Verify real codecs,
  audio, subtitles and Live TV on hardware rather than assuming compatibility.

## Setup and Verification

Install Xcode, XcodeGen, rustup, and the Metal toolchain. The desktop framework
and native converter are fetched/built locally and are never committed:

```bash
./scripts/build_macos.sh
```

Before building, run `security find-identity -v -p codesigning` and set
`CINERAMA_MACOS_SIGNING_IDENTITY` to the installed Apple Development identity.
Keep using the same identity across rebuilds; do not silently fall back to ad hoc
signing on this workstation. See the signing and certificate troubleshooting
steps in `docs/development-workflow.md`. Never commit private keys or certificates.

After code changes, complete this signed, compile-only Mac build before
finishing. TV, shared-source and project changes also require the signed
`scripts/build_tvos.sh` build (see `docs/tvos-prototype.md`). The Mac build verifies
nested signatures and the embedded VLC binary. Run automated tests after code
changes with `scripts/test_macos.sh` and `scripts/test_tvos.sh`; see
`docs/testing.md` for signing, device requirements and coverage. Run both suites
for shared/project/cross-platform changes and the applicable suite for
platform-specific behavior. TV tests default to a local tvOS simulator, so they
also run away from the Apple TV. The default simulator must run tvOS 26.x;
a newer installed runtime must not silently replace that compatibility baseline.
Set `CINERAMA_TVOS_DEVICE_ID` (and team) for an
explicit device run; do not silently skip a requested unavailable-device run.
Simulator support is limited to the maintained TV test workflow; it does not
authorize restoring historical mobile targets/helpers or desktop VLC on TV.
The user has authorized automated test execution, including its required test host.
Do not manually launch apps or perform visual inspection; the user handles visual
and device interaction verification.

For a compiler check after bootstrap only:

```bash
xcodebuild -project Cinerama.xcodeproj -scheme Cinerama-macOS -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/macos/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Do not deliver that unsigned compiler-check product for runtime use. The normal
build script signs the complete bundle with its network sandbox entitlements.
Keep `ENABLE_DEBUG_DYLIB=NO`: macOS uses executable identity/UUID and signing to
track Local Network permission. See `docs/development-workflow.md`.

Run `xcodegen generate` after changing `project.yml` or adding, removing, or
renaming source files. Never hand-edit the generated Xcode project. Use the
pinned rustup toolchain, not Homebrew cargo/rustc, for CineramaDovi.

## Next-Session Handoff

- TV buffering (2026-10-28): the user confirmed the white mask is gone on
  Apple TV Lite after replacing the full-screen Select button's system style.
  One channel then repeatedly froze picture/audio together before resuming.
  TV now opts into a two-second compressed packet reserve (8 MiB / 2048 packets
  plus one in-flight packet), independent of renderer backpressure. Mac defaults
  to no read-ahead. Native demux runs on its own cancellable producer; decode
  metadata uses a snapshot. Both signed builds, 187 Mac tests and all 40 TV tests
  on tvOS 26.0 simulator/Lite pass; native fidelity/fault/buffer/cancellation
  checks pass. A synthetic one-second delivery gap gives 604 ms serial vs 7 ms
  buffered sample waits. Real-channel improvement on Lite is pending user
  verification. The signed app is installed on Lite. See `docs/tvos-live-tv.md`;
  no manual app launch.

- Three-TV setup (2026-10-28): Apple TV 4th plus Apple TV Lite and Apple TV Pro
  (both 3rd-generation 4K) are paired. Signed Cinerama installs succeeded on both
  new TVs; the user reported “all good now.” No agent launch or tests in this
  install-only checkpoint; do not infer a comprehensive playback audit or UHD
  support. Device IDs and signing recovery are in `docs/tvos-prototype.md`.
  With UniFi, pairing succeeded after moving the Mac to the same AP as the TV;
  same VLAN across different APs had not sufficed. Root cause was not isolated.
  Xcode 27.1 uses Device Hub → + → Pair Nearby Device → Apple TV.

- TV UX refinement (2026-10-27): TV-only layouts now use shared TV spacing,
  a smaller Home hero with trailing pager, artwork-led library/season/episode
  grids, a prominent detail Play/Resume action and separate Playback Options.
  Live TV uses aspect-fit logos, search empty states and a compact panel that
  hides after five seconds of playing; direction/Select reveals it. Pause,
  loading, errors, sheets/dialogs and VoiceOver keep controls visible. Native
  tabs, card focus and direct Back-to-channels remain. See `docs/tvos-ui.md`.
  Both signed builds and 40 TV tests on simulator/device pass. The signed TV
  app is installed; fresh user visual/focus acceptance is pending. Earlier
  appearance approval covers the preceding layout. Mac UI is unchanged.

- The user confirmed basic TV Live TV playback works in CPU and Metal modes
  after the atomic cover-presentation fix (2026-10-27), but Metal has severe
  playback delays on Apple TV HD. TV now uses CPU only with no enable/disable toggle or decoder picker;
  the old decoder preference is ignored. Mac CPU/Metal options stay independent. Confirmation covers
  basic playback, not a comprehensive audio, focus or sustained-performance audit.

- TV Live TV now has a separate CPU-only port. Read `docs/tvos-live-tv.md`
  before changing it. `MPEG2Pipeline.swift` shares decoder/render-clock/recovery
  logic; Mac keeps its AppKit/protocol adapter, TV owns its UIKit host and remote
  controls. The TV Live TV tab loads channels immediately. No DVR, captions, seeking,
  Go Live, UHD downscaling or server A/V encoding. TV native slices are built
  separately in `CineramaMPEG2TV.xcframework`; desktop binaries remain excluded.
  Earlier statements below deferring TV Live TV describe the preceding baseline.
  Both signed builds and 40 CPU-only TV tests pass on the tvOS 26 simulator
  and Apple TV HD (2026-10-27). The latest Mac suite passed 186 tests; native
  stream/fidelity/fault checks passed before this TV-only change. The signed TV
  app was installed without manual launch. Basic live-channel playback is now
  user-confirmed; broader audio/focus and sustained-performance checks remain.

- TV target: `CineramaTV/Sources`, scheme `Cinerama-tvOS`. See
  `docs/tvos-prototype.md` for signing, pairing, install and user verification.
  Its Verified Workstation and Devices section records the working build/install
  commands and all three device IDs (2026-10-28). Use `CINERAMA_TVOS_TEAM=JCJFCBSNUG`;
  the signing identity suffix `BZ2K63HJTE` is not the team ID.
  TV now adopts the Mac screening-deck styling through `TVDeckStyle.swift`,
  framed Home/detail viewports and library bays, preserving native TV tabs and
  focus. Both signed builds passed and the user confirmed the installed TV UI
  looks good on 2026-10-25. This confirms appearance; focus/playback behavior
  was not separately confirmed in that feedback.
  `TVStreamResolver` and `TVPlaybackCoordinator` are TV-owned implementations;
  the Mac playback contract is not yet platform-neutral. Keep current
  limitations explicit rather than treating TV as full feature parity.
  Signed TV builds installed on Apple TV HD/tvOS 26.6. The user confirmed the
  Home Screen icon, Plex linking, basic playback and subtitle rendering after
  explicit text-track selection/remux changes. The user reports TV subtitles do
  not yet follow system caption style; this remains unresolved. Confirmation is
  limited to the tried title, not an exhaustive format/style audit. Agents did
  not launch either app or run tests.
  TV now has an artwork-based tab shell, merged Home/search, scoped remembered
  audio/subtitle choices, serialized timeline finalization and a system-caption
  adapter. The user confirmed library artwork and selecting videos to play;
  the UI still needs refinement. The TV icon now derives from the Mac logo via
  `scripts/generate_tvos_icon.swift`. Other new behaviors need user runtime
  verification. TV library Home now reuses the Mac Home data model, with a
  TV-owned hero, personalized shelves, long-press watched/removal actions and
  Show All; see `docs/tvos-home.md`. Live TV remains deferred. The project-wide
  rename uses a new TV application identity; first launch
  requires linking Plex again.

- Native entry and instrument console: `Cinerama/Sources/App/CineramaApp.swift` and
  `Cinerama/Sources/App/MainTabView.swift`. Player controls live in
  `Cinerama/Sources/Features/Player/PlayerView.swift`; Mac settings live in
  `Cinerama/Sources/Features/Settings/SettingsMacView.swift`.
- The signed Debug app is produced at
  `.build/macos/DerivedData/Build/Products/Debug/Cinerama.app`.
- The user confirmed Plex sign-in and Home loading worked after the Mac
  signing/Local Network fix. Permission appearing enabled alone did not fix
  the earlier Home timeout; preserve the signing and executable identity
  settings described above.
- Apple Development signing is now configured and the user confirmed the result
  works. The missing WWDR G3 intermediate was installed from Apple. Preserve
  certificate signing on future builds to avoid repeated Keychain authorization.
- The Mac sidebar has been replaced by a pinned bottom instrument console in
  `MainTabView`. All eight destinations retain independent paths. Navigate uses
  Cmd-1 through Cmd-8; Cmd-F opens Search. The console is hidden with the shell
  during windowed playback. Keep native buttons, readable neutral selection and
  the separate playback host; TV navigation remains independent.
- Player presentation belongs above the whole navigation shell in its own
  stack. Keep catalog stacks mounted but hidden/disabled underneath; replacing
  the split-view detail root can leave a pushed catalog page in front of active
  playback (audio without the player or controls). See `docs/ui-features.md`.
- The user confirmed catalog player presentation, fullscreen entry/exit,
  windowed/fullscreen control-bar alignment, and Home Resume progress-fill
  corners. The player uses one canvas with no navigation toolbar; keep the
  fullscreen toggle and Close icon (`rectangle.portrait.and.arrow.right`) in the
  bottom control bar. Escape exits fullscreen to windowed playback, then closes
  playback on a separate press; there is no top-left Close overlay.
- Mac playback window transfers keep a stable SwiftUI root and renderer host.
  `MacPlaybackWindowState` serializes enter/exit transitions and ignores held
  Escape repeats. Retired-window callbacks must not restore or dismiss a newer
  presentation. See `MacPlaybackWindowTests` for automated sequence coverage;
  the user's reported fullscreen/Resume video loss still needs device confirmation
  after the fix. Agents run automated tests; the user performs visual inspection.
- Controls hide after two seconds, but stay visible while hovered, paused, or
  scrubbing. The compact bar shows series name, season/episode numbers and title.
  The monitor-and-waveform button (Cmd-I) opens safe playback diagnostics.
- Live TV is a searchable channel grid with direct tuning and a channel-card
  Home shelf. This server has no guide data: do not require EPG requests, dates
  or scheduled programs for browsing, tuning or playback titles.
- The user confirmed Live TV plays through VLC with MPEG-2 video and AC3 6ch,
  both copied by Plex without re-encoding. VLC is intentional for this codec.
  The user also confirmed the channel-grid layout and steady live-slider fix
  both work. The slider
  uses the live clock, not the segment-stepped playlist bounds; preserve seek
  clamping to the actual buffer and avoid adding an unseekable five-minute zone.
- Direct/local engine routing considers preferred audio and remembered/current
  subtitles rather than unused tracks. Unsupported choices remain in the menus;
  engine handoffs carry Plex track IDs, position and pause state. Server A/V
  conversion remains prohibited, even for undecodable TrueHD audio.
- Metal enhancement defaults to Auto: eligible SDR up to 50 fps needs at least
  8% upscaling in display backing pixels. Resizing can restore native rendering;
  HDR, selected AVPlayer subtitles and VLC retain native output. M2 image quality,
  hardware decode use and energy performance have not been runtime-profiled.
- Home Recently Added TV resolves episode/season entries to actual show metadata
  on their source server, once per series, including expansion and Show All.
- Pointer feedback on media cards/episode rows belongs only on artwork; the Home
  hero Play/Resume button also has a hand cursor. Video click toggles play/pause,
  double-click toggles fullscreen, and video hover has no tooltip.
  The user confirmed the Mac video keeps the arrow cursor while the control bar
  uses the hand cursor, and Space toggles playback anywhere in the focused player
  window with the pointer inside (2026-10-25). Preserve the window-level Space
  handler independently of control focus and visibility.
- Subtitle choice persists per Plex profile/server/movie or TV series, including
  Off. Appearance comes only from macOS Captions preferences, with a VLC adapter;
  there is no app subtitle-size setting. The menu marks the active selection.
- The user subsequently confirmed that the previously reported missing-subtitle
  issue works now. It is no longer an open investigation; no specific root cause
  was isolated, and this confirmation is not an exhaustive subtitle-format audit.
- Cleanup removed unused player selection/info views, their dormant UI flags and
  diagnostics contract, Mac-only forwarding wrappers, and upstream website/mobile
  screenshot assets. Historical Markdown stays under `docs/upstream/`; the
  current player menus, overlay, subtitle search, and native build inputs remain.
- Automated baseline: 178 Mac tests and 32 TV tests pass (2026-10-25), with TV
  execution on the paired Apple TV HD and tvOS 26.0 arm64 simulator.
  Runtime 26.0 (23J352) is installed locally; `scripts/test_tvos.sh` creates/reuses
  its dedicated simulator. Runtime 27.0 is also installed but is not the default. Both signed builds pass. The earlier
  HDR/Dolby Vision assertion failures have been resolved; see `docs/testing.md`.
  `CineramaTVTests` covers TV resolver/copy-only policy, remembered tracks,
  stopped-session cleanup and native Back dismissal, plus shared library tests.
  Automated hosted tests are authorized; manual/visual verification is user-owned.
  Basic user-confirmed playback is not HDR/Atmos fidelity, offline, or
  comprehensive subtitle runtime verification.
- The user handles browser-based actions. Provide instructions when a browser
  step is needed; use local CLI workflows for authorized repository work.

## Git and Documentation

- Commit completed changes automatically after required verification; do not
  wait for user confirmation. Push periodically at sensible checkpoints, and
  whenever explicitly requested. This is the user's standing preference.
- Check `git status --short` before editing and finishing. Preserve unrelated
  changes; do not revert, stage, or publish another contributor's work.
- `origin` is `kenkenchu/cinerama-player`, the sole development remote. Work on
  `main` unless the user requests a separate branch. Commit and push completed
  work to `origin`; never force-push shared `main`.
- Cinerama follows its own direction. Do not add an upstream remote, fetch or
  merge the original project's changes, or restore upstream-sync workflows
  unless the user explicitly requests it. Preserve the original Git history,
  README credit and license/copyright notices.
- Keep focused docs operational: responsibilities, flow, invariants, extension
  points, traps, and verification. Update matching docs with meaningful changes.
- Docs-only changes need link/reference and diff checks, not a build. If docs
  disagree with source, fix them and mention the correction in the summary.
- User instructions override local skill guidelines and workflow defaults.

## Project-Wide Cinerama Rename

The user chose new application and storage identities. Use schemes
`Cinerama-macOS` and `Cinerama-tvOS` in `Cinerama.xcodeproj`, source trees
`Cinerama`, `CineramaTV`, `CineramaTests`, and `Native/CineramaDovi`. Signing
variables are `CINERAMA_MACOS_SIGNING_IDENTITY`, `CINERAMA_TVOS_TEAM` and
`CINERAMA_TVOS_DEVICE_ID`. Bundle IDs are `com.cinerama-player.mac` and
`com.cinerama-player.tv`; Keychain and downloads use the new namespace. This
requires fresh Plex sign-in/preferences and does not migrate or delete data
from previous app identities. Do not restore old identifiers for convenience.
The native C API is `cinerama_dovi_*` with ABI version 2. Original-project name
and links belong only in README's credit section. Preserve copyright notices.
No analytics endpoint is configured; do not send events to original-project
infrastructure. Settings and privacy documentation describe reporting as disabled.
