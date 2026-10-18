# Dusk Player for Mac — Agent Instructions

This fork, `kenkenchu/dusk-player-mac`, is a **native Mac-first** Plex client with an experimental tvOS feasibility target.
Read this file before planning, editing, committing, or pushing. Read
`AGENTS.local.md` immediately afterward if it exists. Then read
`docs/product-and-scope.md`, `docs/codebase-map.md`, and the relevant topic guide
from `docs/README.md` before discovery-heavy or deep implementation work.

## Platform and Ownership

- The supported app scheme is `Dusk-macOS`: Apple silicon, macOS 26+.
- `project.yml` is the source of truth; XcodeGen produces `Dusk.xcodeproj`.
- `App/` owns app lifetime and sidebar navigation; `Features/Player/` owns the
  native player controls; `Playback/` owns AVPlayer and desktop VLCKit engines.
- Maintain native Mac behavior, keyboard/pointer interaction, resizable windows,
  fullscreen, and Local Network permission handling.
- Historical mobile targets, simulator helpers, TV extensions, and mobile VLC
  frameworks were removed. The new TV prototype does not authorize restoring
  those components when merging upstream updates.
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
  Server video/audio re-encoding is prohibited for all Dusk playback, including
  Live TV, manual quality and audio rescue. HLS may start only after Plex confirms
  both tracks are copied; missing decisions fail closed. Remuxing is allowed.
- Both engines conform to `PlaybackEngine`. Resolver decisions belong in
  `StreamResolver`; orchestration belongs in `PlaybackCoordinator`.
- Minimal dependencies: desktop VLCKit and DuskDovi. New Rust dependencies need
  notices in `Dusk/Resources/ThirdPartyNotices.txt` and the native license list.
- Never log tokens or raw token-bearing media/artwork URLs.

## Style

`STYLE.md` is the visual source of truth: native Mac controls, system materials
and Liquid Glass, neutral palette, no app-wide color tint. Sunset Coral is
reserved for the logo/icon. Follow its typography, spacing, and geometry rules.

## Experimental tvOS Target — Mac UI Protection

- `Dusk-tvOS` is an explicitly requested feasibility prototype, not a supported
  full TV app. Follow `docs/tvos-design.md` and `docs/tvos-prototype.md`; historical
  upstream TV code is reference material only.
- Give tvOS its own app shell, navigation, feature screens, styling, player
  controls and rendering hosts. Apple TV uses remote/focus interaction, not a
  touchscreen. Preserve existing Mac layouts and keyboard/pointer behavior.
- Enforce UI ownership through explicit XcodeGen source membership: neither
  target compiles the other platform's UI. Do not include all `Dusk/Sources`
  indiscriminately in a new TV target or scatter TV branches through Mac views.
- Share platform-neutral Plex/data/session logic. Extract platform adapters
  where needed without changing Mac behavior; keep existing AppKit player hosts.
- Implement in small checkpoints and complete the signed Mac compile after code
  changes. A compile is not visual regression proof: Mac runtime checks require
  explicit user authorization before claiming visual/input parity.
- Preserve the prohibition on server A/V re-encoding on tvOS. Apple TV HD is the
  initial device; prioritize compatible HD SDR media and verify real codecs,
  audio, subtitles and Live TV on hardware rather than assuming compatibility.

## Setup and Verification

Install Xcode, XcodeGen, rustup, and the Metal toolchain. The desktop framework
and native converter are fetched/built locally and are never committed:

```bash
./scripts/build_macos.sh
```

Before building, run `security find-identity -v -p codesigning` and set
`DUSK_MACOS_SIGNING_IDENTITY` to the installed Apple Development identity.
Keep using the same identity across rebuilds; do not silently fall back to ad hoc
signing on this workstation. See the signing and certificate troubleshooting
steps in `docs/development-workflow.md`. Never commit private keys or certificates.

After code changes, complete this signed, compile-only Mac build before
finishing. It verifies nested signatures and the embedded VLC binary. Do not
run tests or launch the app unless the user explicitly asks.

For a compiler check after bootstrap only:

```bash
xcodebuild -project Dusk.xcodeproj -scheme Dusk-macOS -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/macos/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Do not deliver that unsigned compiler-check product for runtime use. The normal
build script signs the complete bundle with its network sandbox entitlements.
Keep `ENABLE_DEBUG_DYLIB=NO`: macOS uses executable identity/UUID and signing to
track Local Network permission. See `docs/development-workflow.md`.

Run `xcodegen generate` after changing `project.yml` or adding, removing, or
renaming source files. Never hand-edit the generated Xcode project. Use the
pinned rustup toolchain, not Homebrew cargo/rustc, for DuskDovi.

## Next-Session Handoff

- Experimental TV target: `DuskTV/Sources`, scheme `Dusk-tvOS`. See
  `docs/tvos-prototype.md` for signing, pairing, install and user verification.
  `TVStreamResolver` and `TVPlaybackCoordinator` are deliberately limited TV
  implementations; the full Mac playback contract is not yet platform-neutral.
  Keep this limitation explicit rather than treating TV as full feature parity.
  Initial signed TV build installed on Apple TV HD/tvOS 26.6; user runtime
  verification is pending. Agents did not launch either app or run tests.

- Native entry and sidebar: `Dusk/Sources/App/DuskApp.swift` and
  `Dusk/Sources/App/MainTabView.swift`. Player controls live in
  `Dusk/Sources/Features/Player/PlayerView.swift`; Mac settings live in
  `Dusk/Sources/Features/Settings/SettingsMacView.swift`.
- The signed Debug app is produced at
  `.build/macos/DerivedData/Build/Products/Debug/Dusk.app`.
- The user confirmed Plex sign-in and Home loading worked after the Mac
  signing/Local Network fix. Permission appearing enabled alone did not fix
  the earlier Home timeout; preserve the signing and executable identity
  settings described above.
- Apple Development signing is now configured and the user confirmed the result
  works. The missing WWDR G3 intermediate was installed from Apple. Preserve
  certificate signing on future builds to avoid repeated Keychain authorization.
- Player presentation belongs above the whole navigation shell in its own
  stack. Keep catalog stacks mounted but hidden/disabled underneath; replacing
  the split-view detail root can leave a pushed catalog page in front of active
  playback (audio without the player or controls). See `docs/ui-features.md`.
- The user confirmed catalog player presentation, fullscreen entry/exit,
  windowed/fullscreen control-bar alignment, and Home Resume progress-fill
  corners. The player uses one canvas with no navigation toolbar; keep the
  fullscreen toggle and Close icon (`rectangle.portrait.and.arrow.right`) in the
  bottom control bar. Escape closes playback; there is no top-left Close overlay.
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
- Latest source changes passed Apple Development-signed compile-only builds;
  agents did not launch the app or run tests. Basic user-confirmed playback is
  not HDR/Atmos fidelity, offline, or comprehensive subtitle runtime verification.
- The user handles browser-based actions. Provide instructions when a browser
  step is needed; use local CLI workflows for authorized repository work.

## Git and Documentation

- Commit completed changes automatically after required verification; do not
  wait for user confirmation. Push periodically at sensible checkpoints, and
  whenever explicitly requested. This is the user's standing preference.
- Check `git status --short` before editing and finishing. Preserve unrelated
  changes; do not revert, stage, or publish another contributor's work.
- `origin` is `kenkenchu/dusk-player-mac`; `upstream` is `marvinvr/dusk-player`.
  Commit and push fork work to `origin` on the current branch unless directed
  otherwise. Never force-push shared `main` or push fork changes to `upstream`.
- Review incoming upstream changes, resolve conflicts deliberately, regenerate
  the project, and verify the Mac build before pushing a merge.
- Keep focused docs operational: responsibilities, flow, invariants, extension
  points, traps, and verification. Update matching docs with meaningful changes.
- Docs-only changes need link/reference and diff checks, not a build. If docs
  disagree with source, fix them and mention the correction in the summary.
- User instructions override local skill guidelines and workflow defaults.
