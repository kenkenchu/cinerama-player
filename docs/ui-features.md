# Native Mac UI

Read this with `STYLE.md`, `codebase-map.md`, and `data-and-plex.md`.
The native Mac app is the only supported UI.

## App and Navigation Shell

`DuskApp` creates the shared services in a single native window. `ContentView`
gates Plex authentication and Home selection, then mounts
`App/MainTabView.swift`. `ServerConnectionCoordinator` connects all enabled
servers beneath the shell and retries on profile, foreground, and network changes.

The shell is a `NavigationSplitView` with fixed Home, Movies, TV Shows, Videos,
Live TV, Search, Downloads, and Settings destinations and per-destination
navigation paths. Cmd-F selects Search. Shared `AppNavigationRoute` values carry
server-scoped identities. Attach `duskAppNavigationDestinations()` inside each
feature's stack. Switching destinations dismisses the active player.

Availability is per server. Connecting or failing servers do not block Downloads
or replace working content. Retry goes through the connection coordinator.
On Mac, unreachable-server UI includes Local Network permission guidance.

## Shared UI

- `DuskAsyncImage` uses the authenticated Plex image pipeline and native images.
- `PosterArtwork`, poster cards and `PlexItemPosterCollections` own artwork,
  subtitles, watched marks, progress, grids, carousels and routes.
- `AdaptivePosterGridLayout` and `DuskPosterMetrics` own responsive geometry.
- `MediaFormatting`/`PlexItemPresentation` own shared media labels and progress.
- `FeatureStateViews` and `ServerAvailabilityViews` own loading/error/outage UI.
- `DetailSharedViews` owns reused detail hero controls and layout helpers.
- `DuskFont` roles resolve native system styles. Theme providers are AppKit
  colors in `Shared/MacPlatform.swift`.

Interactive media thumbnails use the system link cursor and a subtle neutral
hover outline, confined to artwork; card titles, subtitles, and spacing keep the
normal cursor. Season episode rows apply the hand cursor only to playable
artwork; episode text and summary links explicitly use the normal cursor while
retaining their navigation actions. The Home hero Play/Resume button also uses
the link cursor; disabled cards do not advertise a click action. Details links and Show All tiles
include pointer help. Reuse these primitives rather than copying feature-local
implementations.
System controls and neutral states follow `STYLE.md`.

## Home and Libraries

`HomeView` owns loading and refresh; `HomeDesktopView` composes the cinematic hero,
optional Live TV shelf, Plex hubs, then personalized shelves. The desktop hero
Resume button shades its watched fraction using Plex view offset and duration,
clamped to the native button bounds before outer layout sizing. The native
button and fill both use a capsule shape to avoid mismatched corner backgrounds.
The neutral overlay preserves pointer/context-menu
actions and exposes percent watched to accessibility; fresh Play buttons have no
fill. The hero responds to window dimensions and uses `HomeCinematicHeroLayout.desktop`.

`HomeViewModel` merges server payloads and uses `HomeFirstPaintGate` to avoid
rearranging the hero as late servers answer. Preserve the first-paint deadline,
per-profile payload boundary, and late-server merge behavior. Library order
comes from the Plex account; Home has no user-editable row layout.

Recently Added TV contains series only. `PlexService.getHubs` resolves episode
and season entries to real show metadata on their source server, removes repeat
series and retains first appearance (the most recently added content) order.
The same normalization runs before merging expanded rows and Show All results.
Series posters, counts and navigation come from the show, not fabricated episode
data. Metadata requests are bounded to four at a time; unresolved shows are
omitted rather than falling back to episode tiles. Continue Watching and other
episode shelves retain their episode entries.

Library type roots merge recommendations across that type's libraries. Individual
libraries remain server-scoped. Grid models own paging, sorting, genre and
collection filters. Clips use landscape artwork and upload/duration labels.

## Details, Search and Live TV

Movie/show/season/episode/video/person pages have focused observable view models.
Offline-aware models prefer local artwork and account for pending watched/progress
changes. Use the shared route rather than presenting a new detail stack manually.

Search uses the shared carousel presentation and merged Plex/Seerr results.
Seerr pages are request-only and never expose Plex playback/download actions.
Live TV guide behavior belongs in `LiveTVViewModel`. Clicking a channel's
logo/name or its always-available Watch button tunes the live channel, even
without current-program metadata. Current program cards also tune directly;
past/future program cards open details and cannot play that scheduled program.
Historical guide entries are not recordings.

## Player

`Features/Player/PlayerView.swift` is presented in a separate navigation stack
above the whole shell in both windowed and fullscreen playback. The catalog
stack stays mounted, invisible and noninteractive underneath, so a pushed detail
page cannot stay in front of the player when Play is selected. Do not replace a
split-view detail root to present playback: native pushed destinations can remain
in front while audio starts. Closing playback restores the same page and sidebar.
The player hides the navigation toolbar and uses one video canvas in windowed
and fullscreen playback. Controls attach as a bottom overlay of that canvas,
so windowed toolbar/safe-area insets cannot offset them from their background. The bottom control bar contains a fullscreen toggle that
switches between Enter and Exit Full Screen and targets the owning window; it is
not duplicated in the toolbar or top overlay. A Close icon button
(`rectangle.portrait.and.arrow.right`) sits
beside the fullscreen toggle in the control bar; there is no top-left close
overlay. Escape also closes playback, including during loading. In both windowed and
fullscreen playback, controls fade after two seconds of inactivity; pointer
movement or a click reveals them again. Hovering anywhere over the control bar
keeps it visible, including with a stationary pointer. Leaving the bar starts a
fresh two-second timeout. Repeated hover callbacks at the same video position do
not reset the timeout. Scrubbing keeps controls visible, and pausing reveals them.
Leaving fullscreen keeps the same player mounted; closing the player restores
the shell with its previous sidebar visibility and navigation path.
The shell observes its own window, including fullscreen entered with the green
window button or the keyboard shortcut.

Its `MacPlayerSession` uses the common player view model for tracks, scrubbing,
marker skipping, buffering and snapshots. It wires source selection, server
stream changes, fallback, timeline and Up Next through `PlaybackCoordinator`.

| Input | Action |
| --- | --- |
| Click video / Space | Play/pause |
| Double-click video | Toggle native window fullscreen |
| Cmd-I | Toggle playback debug overlay |
| Left / Right | Seek backward/forward 10 seconds |
| Escape | Close player |
| Ctrl-Cmd-F | Native window fullscreen |

The timeline shows elapsed time on the left and remaining time (with a minus
sign) on the right, as M:SS or H:MM:SS. Both preview the scrub position; unknown
duration shows a placeholder. Live TV uses LIVE or time behind live instead of
a finite remaining duration.

The playback control bar uses two compact rows (timeline, then transport and
menus with an inline title showing series name, season/episode numbers, and
episode title for TV episodes), regular native controls with modest padding,
and a translucent neutral black background confined to the padded control bounds. The fill composites over
both native video and letterboxing without sampling a separate AppKit backdrop.
The player explicitly supplies the dark color environment even when the shell
uses light appearance. Reduce Transparency makes the bar's background opaque.

The monitor-and-waveform icon toggle in the playback control bar opens a live
Playback Debug Info overlay. It stays visible independently of control auto-hide and has its own close
button. It shows the engine, route, source codecs, subtitle selection/codec,
transport/buffering state, and renderer geometry/readiness. Plex playback is
shown explicitly as Direct Play, Direct Stream/remux, or Server Transcoding,
with separate video/audio copy-versus-transcode decisions when Plex reports
them. Missing server decisions are marked as unavailable. It never displays
media URLs, tokens, or credentials. This is session UI state, not a saved setting.

The video surface uses a link cursor to advertise its click action, without a
hover tooltip covering the video. Video clicks are handled separately from controls: clicking menus, scrubbing, and toggling
debug info do not toggle play/pause. Double-click is exclusive of single-click.
Player controls include native tooltips naming their keyboard shortcuts. Audio
and subtitle selection use the native menus in `PlayerView`; the old shared
selection sheet and standalone playback-info views have been removed. Auto-hide
is gated by live playback/scrub/hover state, not unused sheet-presentation flags.

Scrubbing previews locally and commits one seek on release. Audio and subtitle
menus use shared selection methods. Playback stays at original quality: no
server-conversion Quality menu is exposed. Undecodable audio choices show a
visible explanation instead of starting server conversion. The subtitle menu uses
a native single-selection picker bound to the active track ID, with a checkmark
on the selected track or Off. Intro/credits and Up Next actions use the coordinator's session identity guards. A ProcessInfo
activity prevents display sleep while the player is mounted.

There are currently no PiP/AirPlay/outgoing SharePlay controls or system media-key
integration. Inherited Group Activities coordination does not imply those UI
features. HDR/audio output and visual layout require runtime validation.

## Settings and Downloads

`SettingsMacView` uses a grouped native form for appearance, playback behavior,
languages, remux toggles, Home settings, downloads, privacy, Seerr,
and account/profile actions. `SettingsContainer` presents Plex Home selection.
The fork has no StoreKit purchasing, supporter prompts or alternate icon picker.

`ServerPrioritySettingsViewModel` writes server priority/enabled state immediately.
`LibraryOrderSettingsViewModel` edits account library order and flushes its
pending Plex write on exit. Server/library rows use the shared native list
editors; do not reintroduce remote focus-driven ordering.

Downloads remain a fixed sidebar destination, including when empty or offline.
Their queue, metadata, disk paths and delayed watch-state sync stay in the
manager layer; see `downloads-and-offline.md`. Subtitle appearance is configured
only in macOS System Settings → Accessibility → Captions; see `playback.md` for
renderer support and limitations. The settings form currently exposes download resolution and network constraints; additional persisted
manager preferences do not imply an existing UI control.

## Verification

Run the signed Mac compile after code changes. Do not launch the app or run tests
unless requested. For authorized visual checks, inspect both themes, resized
windows, keyboard/pointer navigation, error states and player dismissal.
Archived mobile/TV layouts in `upstream/ui-features.md` are historical only.
