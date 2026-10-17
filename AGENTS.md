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
