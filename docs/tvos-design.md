# Maintained tvOS Target

Status: user-confirmed basic playback and text subtitles established feasibility.
The user has authorized maintaining macOS and tvOS in this repository, starting
with TV library playback; Live TV comes later. See [TV UI](tvos-ui.md) and
[device workflow](tvos-prototype.md). Mac and TV have separate native interfaces
and explicitly different feature coverage.

## Device and Initial Scope

The initial device is an Apple TV HD running tvOS 26.6. The user's Plex library
is mostly HD, with little or no known 4K content. Prioritize compatible 720p and
1080p SDR playback. Resolution alone does not establish codec, audio, subtitle
or deinterlacing support. Live TV previously verified on Mac used MPEG-2 and
AC3; its resolution and Apple TV performance remain unverified.

Keep the no-server-A/V-re-encoding policy. Direct play and confirmed copy-only
remuxes remain allowed; unsupported media must fail clearly or offer a compatible
library version. Reject 4K/UHD on Apple TV HD with an informational message and offer an
available HD version. Do not implement 4K software downscaling or introduce
server conversion as a fallback. This TV restriction does not reduce Mac support.

## Protect the Mac Interface

Use a dedicated TV app entry point and remote/focus navigation shell. TV owns
its Home, library, detail, search, profile, settings and player presentation.
Design focus movement, Back behavior and focus restoration after playback for
the remote. Do not adapt the Mac sidebar, hover states or player bar into TV UI.

Keep existing Mac feature views, AppKit hosts, layouts, system styling, window
behavior, keyboard shortcuts and pointer interaction under Mac ownership.
Avoid pervasive `#if os(tvOS)` branches inside Mac views and shared card layouts
that change Mac geometry to accommodate TV focus.

Define explicit source membership in `project.yml`: each target compiles its own
UI and the applicable shared logic, never the other platform's UI. The current
recursive Mac source inclusion must be narrowed or TV sources placed outside
that tree before adding TV code. Generate the project with XcodeGen; do not
hand-edit `Dusk.xcodeproj`.

## Sharing and Playback Boundaries

Reuse platform-neutral Plex models/APIs, server identity and connections,
library-loading logic, watch-state reporting, and suitable view models.
Preferences may be shared where their meaning matches; platform-specific
settings stay separate. Audit dependencies before declaring a type shared:
the Mac playback contract contains AppKit dependencies.
Extract focused platform adapters rather than a general backend abstraction.

Retain `StreamResolver` for Mac routing and `PlaybackCoordinator` for Mac session
orchestration. The TV client uses isolated `TVStreamResolver` and
`TVPlaybackCoordinator` over shared Plex APIs; it does not yet share the AppKit-
dependent `PlaybackEngine` contract. A later extraction must preserve Mac behavior. Add device capabilities without weakening Mac capabilities or
the copy-only Plex decision checks. Preserve the Mac AVPlayer/AppKit and desktop
VLC hosts. TV gets separate rendering hosts, controls and audio-session lifecycle.
Start with AVPlayer and native tvOS playback controls; TVVLCKit requires its own
dependency, renderer and hardware verification. Desktop VLCKit cannot be reused
as a tvOS binary. Shared protocol changes must preserve existing Mac behavior.

Downloads, Metal enhancement and DuskDovi are excluded from the initial TV
milestone. DuskDovi currently builds only for macOS; do not link that binary into
the TV target or make its conversion path a requirement for Apple TV HD.

## Delivery and Verification

The maintained TV client adds native artwork browsing, Home/search,
audio/subtitle preferences, system caption integration and ordered progress
finalization. Library Home now shares Mac's data model with a TV-owned hero,
personalized shelves, watched actions and Show All routes; see [TV Home](tvos-home.md). Upcoming work is runtime hardening against the user's library;
Live TV and broader engine support follow later. Full Mac feature parity is not
a prerequisite for maintaining TV, and must not be claimed from this milestone.

The original feasibility sequence remains useful context:

1. Establish target/source boundaries while preserving the Mac build.
2. Add TV sign-in/profile selection and a minimal browsing shell.
3. Play one representative HD movie with remote controls, resume and Plex
   progress reporting on the actual Apple TV.
4. Expand Home, libraries, details, audio/subtitle selection and settings.
5. Add TVVLCKit and Live TV after basic playback is reliable.

Use small commits. Every code checkpoint requires the existing Apple
Development-signed, compile-only Mac build, preserving signing identity,
entitlements and executable identity settings. Verify the TV target separately
with its own provisioning and appropriate SDK; Mac signing/build scripts are
not TV deployment instructions.

Compilation alone cannot establish unchanged Mac visuals or interaction.
Before claiming parity, obtain explicit authorization for runtime verification
and check Mac navigation, preserved catalog routes, player presentation,
fullscreen entry/exit, control alignment, dismissal, keyboard/pointer behavior,
resizing and appearance. Do not launch either app or run tests without the
authorization required by `AGENTS.md`.

On authorized TV device checks, cover LAN access, focus/Back restoration,
seeking, track selection, subtitle rendering, progress sync, sleep/wake and
sustained playback. Measure representative codecs and Live TV deinterlacing;
record limitations rather than inferring support from resolution or a build.
