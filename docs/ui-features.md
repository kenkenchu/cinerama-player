# Native Mac UI

Read this with `STYLE.md`, `codebase-map.md`, and `data-and-plex.md`.
The Mac interface is maintained independently of the TV interface under
`CineramaTV/Sources`; see [TV design](tvos-design.md) and [TV UI](tvos-ui.md).
TV focus/layout changes must not alter the Mac views described here.

## App and Navigation Shell

`CineramaApp` creates the shared services in a single native window. `ContentView`
gates Plex authentication and Home selection, then mounts
`App/MainTabView.swift`. `ServerConnectionCoordinator` connects all enabled
servers beneath the shell and retries on profile, foreground, and network changes.

The shell is a full-width destination view with a pinned bottom instrument
console, replacing the sidebar. Home, Movies, TV Shows, Videos, Live TV, Search,
Downloads and Settings remain available on every catalog screen. Native buttons
use illuminated icons and permanent caption labels. Three connected bays group
Home/Movies/TV Shows/Videos, Live TV/Search/Downloads, and Settings, preserving
instrument order, 76pt button widths and keyboard shortcuts. The selected button
has a neutral gradient plate, fine outline and steady white lower lamp.
Names and shortcuts also appear in explicit hover labels above the console;
a preference anchor positions them outside the housing clip.

The Liquid Glass housing has swept shoulders, double rails and short static
index marks. Smoked metallic-blue bay fills and fine dividers define the panel.
`ViewThatFits` drops the wordmark first when space is tight, keeping all eight
instruments visible at the supported 900pt minimum window width. The compact
housing is 746pt wide (eight 76pt instruments, intra-bay gaps, bay padding,
dividers and housing padding), plus 40pt outside margins.
Reduce Transparency substitutes opaque metallic-blue housing/bay surfaces.
Decoration is noninteractive and accessibility-hidden. `CockpitInstrumentStyle`
retains native ButtonStyle pressed feedback and pointer hover without animation
timers. Mac-only styling leaves TV navigation and player controls unchanged.

Each destination retains its own `NavigationPath`. The Navigate menu supplies
Cmd-1 through Cmd-8 in instrument order; Cmd-F still selects Search. The obsolete
Show/Hide Sidebar command is removed. Shared `AppNavigationRoute` values carry
server-scoped identities. Attach `cineramaAppNavigationDestinations()` inside each
feature's stack. Switching destinations dismisses the active player; selecting
the current instrument preserves its pushed route. Entering Search remembers
the previous destination. The toolbar magnifying glass posts the same Search
command as Cmd-F instead of pushing an independent Search route, so the toolbar,
instrument and menu all share that return destination. Escape restores it and
its saved path, including while
the native search field owns focus. Repeated Search selection does not overwrite
the return destination. The catalog-window Escape monitor ignores modified keys,
other windows, attached sheets and active playback, leaving player dismissal and
sheet cancellation to their existing owners.

Availability is per server. Connecting or failing servers do not block Downloads
or replace working content. Retry goes through the connection coordinator.
On Mac, unreachable-server UI includes Local Network permission guidance.

## Shared UI

- `CineramaAsyncImage` uses the authenticated Plex image pipeline and native images.
- `PosterArtwork`, poster cards and `PlexItemPosterCollections` own artwork,
  subtitles, watched marks, progress, grids, carousels and routes.
- `AdaptivePosterGridLayout` and `CineramaPosterMetrics` own responsive geometry.
- `MediaFormatting`/`PlexItemPresentation` own shared media labels and progress.
- `FeatureStateViews` and `ServerAvailabilityViews` own loading/error/outage UI.
- `DetailSharedViews` owns reused detail hero controls and layout helpers.
- `CineramaFont` roles resolve native system styles. Theme providers are AppKit
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

TV now reuses `HomeViewModel` and its data helpers, with separate native TV
views and routes. See [TV Home](tvos-home.md). The Mac presentation below stays
unchanged; its personalized Show All route adapter is Mac-only.

`HomeView` owns loading and refresh; `HomeDesktopView` composes the cinematic hero,
optional Live TV shelf, Plex hubs, then personalized shelves. The desktop hero
Resume button shades its watched fraction using Plex view offset and duration,
clamped to the native button bounds before outer layout sizing. The native
button and fill both use a capsule shape to avoid mismatched corner backgrounds.
The neutral overlay preserves pointer/context-menu
actions and exposes percent watched to accessibility; fresh Play buttons have no
fill. The hero responds to window dimensions and uses `HomeCinematicHeroLayout.desktop`
with compact typography for smaller windows. Its panel padding is deducted from
the available title width to keep content inside the viewport.

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
Live TV is a channel browser, with an adaptive grid of landscape logo/name/number
cards, native name/number search, a count, Refresh/Retry and loading/empty states.
Every card tunes immediately, shows a hand cursor and play affordance on hover,
and marks the active server-scoped channel. There is no date picker, program
timeline, schedule detail sheet or empty guide placeholder. The optional Home
Live TV shelf reuses the channel cards and also works without EPG data.
`LiveTVViewModel` loads provider/channels only, shares in-flight loading between
Home and the tab, and builds a channel-only lineup for playback. The control bar
shows the channel display name and LIVE status rather than a program title.

## Player

`Features/Player/PlayerView.swift` is presented in a separate navigation stack
above the whole shell in both windowed and fullscreen playback. The catalog
stack stays mounted, invisible and noninteractive underneath, so a pushed detail
page cannot stay in front of the player when Play is selected. Do not replace a
split-view detail root to present playback: native pushed destinations can remain
in front while audio starts. Closing playback restores the same page and
instrument console.
Windowed Mac playback extends video through the title-bar area and hides the title,
separator, traffic-light buttons and shadow, retaining native resizing and keyboard
focus. The titled AppKit style stays enabled so the existing window can become key. Closing playback
restores catalog window decoration; detaching fullscreen restores it for the
visible catalog window, and returning to inline playback removes it again.
The player control bar supplies Close and fullscreen actions; Escape keeps its
existing behavior. `MacPlaybackWindowChrome` owns the reversible decoration
snapshot. TV presentation is unchanged.
The player hides the navigation toolbar and uses one video canvas in windowed
and fullscreen playback. Controls attach as a bottom overlay of that canvas,
so windowed toolbar/safe-area insets cannot offset them from their background. The bottom control bar contains a fullscreen toggle that
switches between Enter and Exit Full Screen using a separate playback window; it is
not duplicated in the toolbar or top overlay. A Close icon button
(`rectangle.portrait.and.arrow.right`) sits
beside the fullscreen toggle in the control bar; there is no top-left close
overlay. Escape exits fullscreen while keeping playback running; in windowed
playback it closes the player, including during loading. The playback host handles Escape for its own key window
independently of SwiftUI focus, and leaves attached sheets to handle cancellation.
In both windowed and
fullscreen playback, controls fade after two seconds of inactivity; pointer
movement or a click reveals them again. Hovering anywhere over the control bar
keeps it visible, including with a stationary pointer. Leaving the bar starts a
fresh two-second timeout. Repeated hover callbacks at the same video position do
not reset the timeout. Scrubbing keeps controls visible, and pausing reveals them.
Fullscreen reparents the same player hosting view into a dedicated native window,
leaving the catalog visible in the main app window at its existing size and
fullscreen state. The playback window starts on the same display as windowed
playback, using its screen-space bounds rather than window-local coordinates. Exiting
fullscreen moves that hosting view back above the catalog without restarting the
player session. View disappearance during this transfer releases UI timers and
display-sleep activity without pausing the engine; reappearance restores those
resources without repeating track selection. Playing and paused states are
preserved in both directions. Closing playback (including the separate window) restores the
shell with its previous destination and navigation path. The main window's
green button remains independent; the player button, double-click and Ctrl-Cmd-F
use the playback window.

Its `MacPlayerSession` uses the common player view model for tracks, scrubbing,
marker skipping, buffering and snapshots. It wires source selection, server
stream changes, fallback, timeline and Up Next through `PlaybackCoordinator`.

| Input | Action |
| --- | --- |
| Click video / Space | Play/pause |
| Double-click video | Toggle separate playback fullscreen |
| Cmd-I | Toggle playback debug overlay |
| Left / Right | Seek backward/forward 10 seconds |
| Escape | Exit fullscreen; close player when windowed |
| Ctrl-Cmd-F | Toggle separate playback fullscreen |

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

The video surface keeps the standard arrow cursor, without a hover tooltip
covering the video. The playback control bar uses the hand cursor. Video clicks
are handled separately from controls: clicking menus, scrubbing, and toggling
debug info do not toggle play/pause. Double-click is exclusive of single-click.
Player controls include native tooltips naming their keyboard shortcuts. Audio
and subtitle selection use the native menus in `PlayerView`; the old shared
selection sheet and standalone playback-info views have been removed. Auto-hide
is gated by live playback/scrub/hover state, not unused sheet-presentation flags.

Unmodified Space toggles playback anywhere in the focused player window while
the pointer is inside it, independent of the focused control or hidden controls.
`MacPlaybackSpaceHandler` intercepts the key at the AppKit window boundary and
calls the same view-model action as Play/Pause. It consumes key repeats without
toggling again, leaves modified shortcuts and attached sheets alone, follows
the current window during fullscreen reparenting, and removes its monitor when
the player is dismantled. This is Mac keyboard/pointer behavior; TV retains its
native remote transport controls.

On 2026-10-25, the user confirmed both Mac playback changes work: the arrow
cursor over video with the hand cursor on the control bar, and Space toggling
play/pause across the focused playback window with the pointer inside. Agents
did not launch the app or run tests.

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

`SettingsMacView` uses a grouped native form describing the fixed Cinematic
Metal Blue theme, plus playback behavior,
languages, remux toggles, Home settings, downloads, privacy, Seerr,
and account/profile actions. `SettingsContainer` presents Plex Home selection.
The fork has no StoreKit purchasing, supporter prompts or alternate icon picker.

`ServerPrioritySettingsViewModel` writes server priority/enabled state immediately.
`LibraryOrderSettingsViewModel` edits account library order and flushes its
pending Plex write on exit. Server/library rows use the shared native list
editors; do not reintroduce remote focus-driven ordering.

Downloads remain a fixed instrument destination, including when empty or offline.
Their queue, metadata, disk paths and delayed watch-state sync stay in the
manager layer; see `downloads-and-offline.md`. Subtitle appearance is configured
only in macOS System Settings → Accessibility → Captions; see `playback.md` for
renderer support and limitations. The settings form currently exposes download resolution and network constraints; additional persisted
manager preferences do not imply an existing UI control.

## Verification

Run the signed Mac compile and automated tests after code changes. Leave
manual app launches and visual inspection to the user. For authorized visual checks, switch the system appearance
while checking that the app stays metallic-blue, then inspect resized
windows, keyboard/pointer navigation, error states and player dismissal.
Archived mobile/TV layouts in `upstream/ui-features.md` are historical only.

## Futuristic Mac presentation

`MainTabView` presents the destinations as a bottom cockpit instrument console
with a Cinerama wordmark when space permits. Per-destination paths and the
separate playback host are retained.
`HomeCinematicHero` places its title/actions in a dark framed panel with a
featured/continue-watching label; its dark environment preserves readable copy
in light appearance. `MediaCarousel` supplies ruled headings, while
`PosterArtwork` and `MacMediaCardInteraction` supply fine edges and artwork-only
hover illumination. The player transport gains the same neutral edge treatment.
No TV views or playback/data decisions change. Signed compilation is the agent
verification gate; system-appearance switching, resized-window and input inspection remain user
runtime verification.

## Home Spacecraft Cinema

`HomeDesktopView` composes a Screening deck header, inset hero viewport and
material library bays above the static `HomeDeckBackground`. The Mac-only
`HomeSpacecraftChrome.swift` owns the background, header, viewport brackets and
bay modifier; it has no timers, Plex requests, focus handling or hit targets.
Decorative layers are accessibility-hidden and do not intercept artwork clicks,
hero drags, context menus or scrolling. Featured counts and the viewport index
come from existing hero data; no connection/codec/quality state is fabricated.

The hero retains its rotation/pager, Play/Resume progress and actions. It uses a
rounded 28pt viewport with a fine frame; Home's toolbar is visible in the current
appearance. Library bays wrap nonempty Plex/personalized shelves and populated
Live TV only. Reduce Transparency substitutes opaque surfaces. The prior empty
88pt bottom inset is removed; normal bottom content padding remains. Loading,
error and outage routes remain owned by `HomeView`. TV does not compile any of
these Mac view types. Verify independence from system appearance, narrow windows, long titles, hero drag,
pager, Show All and return from playback when runtime inspection is authorized.

The console is inserted outside the destination NavigationStack using a bottom
safe-area inset, reserving space rather than covering the last content row.
The whole catalog shell, including its instruments, stays mounted but hidden
and disabled beneath windowed playback. Detached fullscreen keeps the catalog
window's console visible. `MacPlaybackHost` owns stable-root window transfers and serialized fullscreen/Escape handling. Runtime checks should cover all eight instruments, the Navigate
menu/shortcuts, narrow-window instruments, back navigation and return from playback.

While the pointer is inside the visible Home hero, unmodified Left/Right arrows
select the previous/next featured item through the same transition and rotation
reset as the existing hero actions, including wraparound. `HomeHeroArrowKeys`
checks its hosting window and clipped visible bounds rather than moving keyboard
focus. It passes keys through outside the hero, while editing text, while a sheet
is attached, during a drag, off Home or during playback. The local event monitor
is removed with its view. Runtime verification should include hover over both
artwork and the information panel, scroll-off, text entry, and player seeking.

## Fixed Metal Blue Appearance and Liquid Glass

`CineramaApp` pins both AppKit appearance and SwiftUI color scheme to dark;
`MacPlatform.swift` defines the lighter metallic-blue page/surface palette. Existing
saved appearance-mode preferences no longer affect the app, and Settings now
names the fixed theme instead of offering System/Light/Dark. Separate playback
windows inherit the app's native appearance. System caption appearance remains
controlled by macOS accessibility preferences.

`MainTabView` uses native `glassEffect` on the chamfered console, with an opaque
surface for Reduce Transparency. Home and detail primary actions use neutral
prominent glass buttons; secondary detail actions use regular glass buttons.
Home library bays use metallic-blue surfaces beneath the glass control layer.
The player transport keeps its existing compositing fill. Compilation does not
verify runtime contrast or appearance-switch behavior.

The main window uses `CineramaWindowBackdrop` over a clear window container.
Its single `NSVisualEffectView` samples behind the window, with a metal-blue
clear Liquid Glass treatment. Catalog/auth/loading backgrounds are clear instead
of stacking solid page fills; Home's static stars/grid remain over this backdrop.
Reduce Transparency swaps in the opaque metal-blue background. Native forms,
artwork fades and player surfaces retain their own readability/compositing fills.
The signed Mac compile passed; desktop transparency and contrast need user visual
verification, and agents did not launch the app or run tests.

## Playback Window Sequence Hardening

`MacPlaybackContent` stays the same typed SwiftUI root through fullscreen entry
and exit. Only its observable presentation flag changes; do not replace the
hosting view's root/navigation stack while moving a shared engine renderer.
`updateNSView` remembers the current inline container and repairs attachment
when inline. Restore attaches and lays out the host before clearing detached
state, closing the retired fullscreen window and focusing the main window.

`MacPlaybackWindowState` separates inline, entering, fullscreen, exiting and
closed phases. Escape repeats and commands during transitions are consumed;
leaving fullscreen cannot turn a held Escape into a windowed Close. Native
fullscreen callbacks use the same state transitions, and callbacks are accepted
only from the currently owned window. Teardown marks the host closed before
removing the view/window so late delegate events cannot restore it. Both the
SwiftUI Exit command and key monitor route through this policy. TV's native
AVKit fullscreen presentation is independent of this Mac window lifecycle.

Automated sequence coverage in `MacPlaybackWindowTests` exercises Escape,
repeated transitions, failed entry/exit, native exit, closing mid-transition and
fresh state after dismissal/Resume. AppKit attachment tests additionally verify
host identity and layout through reparenting, inline-container replacement, and
retired-host teardown after a new presentation. The focused run passed all 18
tests across the two window suites and playback recovery suite. Both signed
builds passed. The later cross-platform testing checkpoint resolved the earlier
Dolby Vision/10-bit H.264 assertion failures; all 178 Mac tests now pass.
See [Automated testing](testing.md) for the current Mac/TV coverage baseline.
These checks do not prove rendered video.
The user should retry fullscreen → Escape → windowed playback, then close and
Resume, for both playing and paused sessions; visual inspection is user-owned.

## Mac Live TV Decoder Experiment

Settings offers Standard playback, Experimental CPU and Experimental Metal for
MPEG-2 Live TV. Changes apply on retune; forced engine preferences and AirPlay
retain priority. The experimental player shows its hybrid IDCT path and GPU block
count in Cmd-I. It disables seek and subtitle controls. The Mac player has no
Go Live button because Live TV DVR is outside scope. LIVE markers in the playback
title, live-position readout and debug position are red; channel names and
behind-live offsets retain their normal styling. Audio tracks can be selected;
PCM channel count/rate are shown in diagnostics. Caption limitations are
explained beside the setting. DVR is out of scope; interlaced output is deinterlaced at field rate. Other Mac
playback and the TV UI keep their existing behavior.
See [playback](playback.md#experimental-metal-mpeg-2-reconstruction) and the
[native experiment](../Native/CineramaMPEG2/README.md). No visual/input runtime
verification is claimed by builds or hosted tests.
