# macOS and tvOS Codebase Map

`project.yml` defines the native `Cinerama-macOS` app, hosted Mac tests, and an
maintained `Cinerama-tvOS` app for Apple TV HD. TV sources live in `CineramaTV/Sources`
outside the Mac UI tree and explicitly reuse models/services; see
[TV device workflow](tvos-prototype.md).
`Cinerama/Sources` has no mobile shell, TV HUD/extension, or mobile VLC renderer.

## Source Layout

```text
Cinerama/Sources/
  App/              CineramaApp, auth gate, instrument-console MainTabView, routes, server connection lifecycle
  Analytics/        Anonymous app-open event and reporting transport
  Models/           Plex/Seerr response models and app media types
  PlexService/      Auth, server pool, account/server APIs, images, playback URLs
    MultiServer/    Cross-server merging and alternates
  SeerrService/     Optional request companion and credential boundary
  Playback/         PlaybackEngine, AVPlayer/AppKit and desktop VLC engines, resolver, Metal
    DolbyVision7/   HLS loopback proxy, init/fragment rewriting, DoviBridge
  Downloads/        Queue, file store, metadata cache, offline sync
  Shared/           AppKit theme, typography, artwork, cards/grids, formatting, recommendations
  Features/
    Account/        Sign-in and Plex Home picker
    Home/           HomeDesktopView, hero, hubs and recommendation view models
    Libraries/      Library roots, grids, collections and recommendations
    Detail/         Movie/show/season/episode/video/person detail flows
    LiveTV/         Searchable channel browser, lineup and tuned-channel presentation
    Player/         Native PlayerView, coordinator, track logic, timeline and Up Next
    Downloads/      Downloaded library and queue UI
    Search/         Search UI, merged Plex/Seerr results
    Settings/       SettingsMacView, preferences, server/library editors, Seerr setup
    Seerr/          Request-only detail screens
  Siri/             Inherited App Intents/title matching; Mac runtime behavior unverified
CineramaTV/Sources/     TV app/auth gate, tab shell, artwork, Home/search, library/details,
                    TVStreamResolver, TVPlaybackCoordinator, scoped track preferences,
                    native AVKit host and system-caption adapter
Native/CineramaDovi/     Mac Rust Dolby Vision conversion crate and C header
CineramaTests/          Retained shared model/service tests hosted by the Mac app
```

## App Lifetime and Navigation

`CineramaApp` creates Plex/Seerr services, preferences, analytics, download manager,
offline sync, and `PlaybackCoordinator`. It registers inherited App Intents and
injects the long-lived services into a single native window.

`ContentView` routes unauthenticated users to `SignInView`, waits for Plex Home
bootstrap, optionally presents the profile picker, then opens `MainTabView`.
`ServerConnectionCoordinator` connects enabled servers under the shell, refreshes
on session/foreground/network changes, and exposes Retry to screens.

`App/MainTabView.swift` owns the full-width shell, pinned bottom instrument
console, Navigate menu commands and per-destination paths. Home, Movies, TV
Shows, Videos, Live TV, Search, Downloads, and Settings are fixed instruments. Player presentation is a separate navigation
stack above the entire shell. The shell stays mounted but hidden during playback
to preserve pushed detail routes and prevent them from covering the player.
`AppNavigationRoute` carries server-scoped identities into detail/library flows.

## Feature Owners

- Home: the shared `HomeViewModel` and pure helpers serve both platforms. Mac
  `HomeView` owns loading and first paint; `HomeDesktopView` composes the
  hero and shelves. `HomeViewModel` merges every server, with
  `HomeFirstPaintGate`, hub filters/arrangement, and recommendation engines.
- Libraries: `LibrariesViewModel` reads account library order;
  `LibraryItemsViewModel` owns paging/sort/filter; recommendation models own
  merged type shelves. Libraries remain distinct per server.
- Details: media-specific view models fetch Plex/cache data. Reusable hero and
  detail controls live in `DetailSharedViews.swift`; shared cards live in
  `Shared/`. Show/season/episode each have their own native route.
- Player: `PlaybackCoordinator` owns source/session/recovery/timeline/Up Next;
  `PlayerViewModel` owns interaction, tracks, marker skipping, and sync.
  `Features/Player/PlayerView.swift` is the native Mac UI.
- Engines: `Playback/AVPlayerEngine.swift` hosts `AVPlayerLayer` in AppKit;
  `Playback/VLCKitEngine.swift` uses desktop `VLCVideoView` and Core Audio.
  `PlaybackEngineFactory` and `StreamResolver` choose engines.
- Downloads: `DownloadManager` orchestrates the queue; `DownloadTransferController`
  handles URLSession delegates; `DownloadFileStore` owns contained paths;
  `OfflinePlaybackSyncManager` owns delayed watch-state sync.
- Settings: `SettingsMacView` is the grouped native form. `UserPreferences` owns
  device-local values; server priority and library order retain focused view
  models and Plex/account ownership rules.
- Seerr: `SeerrService` is an optional request companion, never a playback backend.

## Shared Boundaries and Extension Points

Use `CineramaAsyncImage` for Plex-aware artwork, `PlexItemPresentation` and
`MediaFormatting` for labels/progress, `CineramaPosterMetrics` for geometry,
`CineramaFont` for semantic roles, and `FeatureStateViews`/`ServerAvailabilityViews`
for loading, errors and per-server availability. Theme providers are AppKit
`NSColor`s in `Shared/MacPlatform.swift`. Native SwiftUI navigation, toolbar and list APIs and
AppKit `NSImage` are used directly, without mobile platform-selection wrappers.

Add new Plex endpoints to the matching `PlexService+*.swift` extension and new
response shapes to `Models/`. Routing belongs in `AppNavigationRoute`.
New Mac-specific UI belongs beside its feature. Engine behavior stays behind
`PlaybackEngine`; Dolby Vision conversion remains behind `DoviBridge`.

## Invariants

- Rating keys collide across servers: identity is `PlexItemID`.
- `PlexContentKey` is cross-server sameness, not a request/storage identifier.
- Every follow-up playback call uses `activePlaybackServerID`, never an
  arbitrary primary server. One server failing cannot invalidate others.
- Only strong content keys register playback alternates; duplicate copies on
  one server must never become an accidental file/version fallback.
- Downloads/cache/watch sync are profile- and server-scoped.
- Plex account settings such as library order stay on Plex; local display and
  playback preferences stay in UserDefaults.
- Direct play is the baseline; server A/V re-encoding is prohibited. HLS remuxes
  require confirmed video and audio copying before a start URL is constructed.
- XcodeGen must run after source changes. Verify the native Mac build and update
  the relevant guide in the same change.

## Platform Boundary Gate

`scripts/verify_platform_boundaries.py` reads the generated project and rejects
TV inputs in Mac, Mac UI/engine inputs in TV, and desktop playback frameworks in
TV. Both build scripts run it after XcodeGen. The TV shared-source allowlist is
models, PlexService, explicitly listed Home/library view models and domain
helpers (including the shared model's SwiftUI animation calls). Mac views and
Mac route adapters remain excluded. Extend the
boundary deliberately when extracting genuinely reusable logic; never blanket-
include Mac features to resolve a TV compile error.

TV Home presentation and direct hero playback live in `TVHomeView`,
`TVHomeHero`, `TVHomePlaybackModel` and `TVHomeGrids`; see [TV Home](tvos-home.md).
The existing Mac Home view/layout code remains platform-owned. Shared genre
models, library identity hashing and watched-action availability were extracted
from Mac files without changing their definitions.
