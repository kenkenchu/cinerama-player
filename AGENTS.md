# Dusk Player for Mac — Agent Instructions

This fork, `kenkenchu/dusk-player-mac`, is a **native macOS-only** Plex client.
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
- Mobile targets, simulator helpers, TV extensions, and mobile VLC frameworks
  have been removed. Do not reintroduce them when merging upstream updates.
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
  Manual transcoding is a per-session Quality action; never persist a startup
  quality default that automatically re-encodes future playback.
- Both engines conform to `PlaybackEngine`. Resolver decisions belong in
  `StreamResolver`; orchestration belongs in `PlaybackCoordinator`.
- Minimal dependencies: desktop VLCKit and DuskDovi. New Rust dependencies need
  notices in `Dusk/Resources/ThirdPartyNotices.txt` and the native license list.
- Never log tokens or raw token-bearing media/artwork URLs.

## Style

`STYLE.md` is the visual source of truth: native Mac controls, system materials
and Liquid Glass, neutral palette, no app-wide color tint. Sunset Coral is
reserved for the logo/icon. Follow its typography, spacing, and geometry rules.

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
  fullscreen toggle in the bottom control bar and Close over the video.
- Controls hide after two seconds, but stay visible while hovered, paused, or
  scrubbing. The compact bar shows series name, season/episode numbers and title.
  The monitor-and-waveform button (Cmd-I) opens safe playback diagnostics.
- Pointer feedback on media cards/episode rows belongs only on artwork; the Home
  hero Play/Resume button also has a hand cursor. Video click toggles play/pause,
  double-click toggles fullscreen, and video hover has no tooltip.
- Subtitle choice persists per Plex profile/server/movie or TV series, including
  Off. Appearance comes only from macOS Captions preferences, with a VLC adapter;
  there is no app subtitle-size setting. The menu marks the active selection.
- Pending investigation: after the system-caption-style change the user reported
  selected subtitles missing on some files. This was deferred for the catalog
  presentation fix and remains unresolved. Identify an affected file/track and
  engine using the overlay before changing rendering or routing again. Do not
  describe the subtitle issue as fixed or assume all files/engines are affected.
- Latest source changes passed Apple Development-signed compile-only builds;
  agents did not launch the app or run tests. Basic user-confirmed playback is
  not HDR/Atmos fidelity, offline, or comprehensive subtitle runtime verification.
- The user handles browser-based actions. Provide instructions when a browser
  step is needed; use local CLI workflows for authorized repository work.

## Git and Documentation

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
