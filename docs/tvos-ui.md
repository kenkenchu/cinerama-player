# Native Apple TV UI

The TV interface is owned by `DuskTV/Sources`. `STYLE.md` governs the Mac UI;
this guide governs TV layouts and remote interaction. Never adapt Mac controls
or card geometry to satisfy the TV focus engine.

## Shell and Catalog

`TVRootView` gates Plex linking and Home profile selection. `TVCatalogShell`
keeps a separate navigation stack mounted for Home, Libraries, Search and
Settings. `TVAppModel` owns account/profile lifecycle and catalog refresh.
Refresh leaves the shell mounted; a profile change clears the catalog and
invalidates old async results. Sign-out is confirmed in the TV Settings form.

Home now matches Mac library Home behavior through the shared `HomeViewModel`:
a cinematic Continue Watching hero, filtered/library-ordered Plex hubs,
personalized genre shelves, watched actions and Show All routes. See
[TV Home feature mapping](tvos-home.md) for the exact scope and verification.
Library order comes from the existing Plex account ordering service. Libraries
remain distinct per server; search and Home reuse the shared merge functions.
A failing server is reported without emptying working servers' content.
Library pages use explicit Load More controls; search is debounced and cancels
superseded queries. Unsupported search types are omitted rather than routed to
unimplemented detail screens. Settings offers profile switching, server refresh,
connection status and playback/caption information.

## Artwork, Layout and Focus

Use native SwiftUI tabs, navigation, forms, buttons and card focus effects.
The initial TV appearance is dark and neutral, without a custom global tint.
Sunset Coral remains a logo/icon color. Use system typography, generous gaps
and readable titles; avoid Mac pointer/hover rules and fixed window assumptions.

`TVArtwork`/`TVArtworkModel` load server-authenticated, dimensioned artwork using
PlexService. The in-memory cache is capped at 32 MiB/120 images and scoped by
profile, server and request. Lazy shelves/grids bound visible loading work for
the A8. Poster artwork is 220 × 330 points with a 16-point radius; shelves use
38-point card gaps and 60-point horizontal margins. Grids adapt to available
width with native focus treatment. Titles and episode labels sit below artwork;
partial progress appears as a neutral bar over artwork.

Stable server-scoped item IDs preserve card identity. Returning from details
must keep the parent navigation stack and its focus context. Fullscreen playback
is presented above the detail route and tab shell. Back should first follow
native AVKit controls, then return to details; app-owned dismissal is wired
through the native player delegate. Device focus restoration is still a runtime
verification requirement, not a compiler guarantee.

## App Icon

The TV icon reuses the Cinerama West Coast glass C from the Mac Icon Composer
source, centered on a midnight-blue gradient matching the Mac composition.
Sunset coral/amber and Pacific teal/blue are confined to the brand mark; see
[icon design](icon-design.md) for the master and generation prompt.
Foreground and background remain separate native TV parallax layers. Do not
bake a rounded mask or a second square Mac icon inside the TV tile.

Run `swift scripts/generate_tvos_icon.swift` after changing the Mac logo source.
It packages the existing artwork into 400 × 240 (1×/2×) Home Screen and
1280 × 768 App Store stacks under `DuskTV/Resources/Assets.xcassets/TVIcon.brandassets`.
The generated PNGs are committed; the unmasked review preview stays in `.build/`.
The script does not alter Mac icon assets or require them in the TV app bundle.

## Details and Playback

Details show artwork, title, year, summary and season/episode routes. Each
media version offers compatible audio and text subtitle choices before
Play/Resume. Unsupported tracks remain explanatory text rather than selectable
routes that would require server conversion. Track choices are remembered on
the device per Plex profile/server/movie or TV series; Off is explicit.
Selections match semantic track properties rather than carrying an episode's
stream IDs into another file. Track changes take effect on the next Play/Resume.

`TVStreamResolver` owns Apple TV HD eligibility. Reject 4K/UHD with a clear
informational message and offer other HD versions if Plex has them. Do not
implement software downscaling or server conversion as a rescue. HDR and other
unsupported formats also explain why the version cannot play. Mac capability
routing remains independent.

`TVPlaybackCoordinator` owns native AVPlayer sessions, copy-only HLS, track
mapping, caption appearance, timeline serialization and finalization. Pause,
play, buffering, periodic progress and dismissal use server-scoped reporting.
On natural completion, mark the item watched. Details/Home refresh after the
final stopped timeline and remux cleanup complete, avoiding stale resume data.
Playback pauses on backgrounding. Native AVKit supplies transport and seeking;
no custom TV transport bar is shared with Mac.

Caption appearance has no Dusk picker. `TVSystemCaptionStyle` translates the
Apple TV system's explicit user overrides into WebVTT style rules for font,
relative size, text/background/window colors, opacity and edge treatment.
Properties permitting authored content to override remain under native control.
Refresh the rules on settings notifications and foreground entry. This adapter
needs user visual verification; advanced authored ASS formatting and bitmap
caption styling are not promised. It does not alter Mac caption behavior.

The Playback Information route shows safe delivery, subtitle availability and
progress-sync state.
Never expose media/artwork URLs, tokens or credentials in these diagnostics.

## Verification

Run both signed builds and the generated-project platform-boundary check.
The build scripts run this structural check automatically after XcodeGen.
Install the signed TV build on Apple TV HD for user verification. Agents do not
launch apps or run tests unless explicitly requested. Verify Home/library
browsing, search, focus/Back, paging, direct/remux playback, audio/subtitles,
remembered Off across episodes/profiles, system captions, progress/resume and
completion. Mac visuals/input need their own authorized runtime check.
