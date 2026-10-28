# Native Apple TV UI

The TV interface is owned by `CineramaTV/Sources`. `STYLE.md` governs the Mac UI;
this guide governs TV layouts and remote interaction. The TV presentation follows
the Mac screening-deck visual language through TV-owned components; Mac controls
and card geometry remain independent of the TV focus engine.

## Shell and Catalog

`TVRootView` gates Plex linking and Home profile selection. `TVCatalogShell`
keeps a separate navigation stack mounted for Home, Libraries, Search and
Settings and experimental Live TV. `TVAppModel` owns account/profile lifecycle and catalog refresh.
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
connection status and playback/caption information. Libraries use artwork-led
collection cards with server labels rather than a setup-style list.

## Artwork, Layout and Focus

Use native SwiftUI tabs, navigation, forms, buttons and card focus effects.
The TV appearance is fixed Cinematic Metal Blue, independent of system theme,
without a custom global control tint.
Sunset Coral remains a logo/icon color. Use system typography, generous gaps
and readable titles; avoid Mac pointer/hover rules and fixed window assumptions.

`TVArtwork`/`TVArtworkModel` load server-authenticated, dimensioned artwork using
PlexService. The in-memory cache is capped at 32 MiB/120 images and scoped by
profile, server and request. Lazy shelves/grids bound visible loading work for
the A8. Poster artwork is 220 × 330 points with a 16-point radius; shelves use
40-point card gaps and 80-point horizontal content margins. Page content uses
60-point vertical padding inside native safe areas; focus expansion has its own
room between cards. `TVDeckLayout` owns these TV-only values. Grids adapt to available
width with native focus treatment. Titles and episode labels sit below artwork;
partial progress appears as a neutral bar over artwork.

Stable server-scoped item IDs preserve card identity. Returning from details
must keep the parent navigation stack and its focus context. Fullscreen playback
is presented above the detail route and tab shell. Back should first follow
native AVKit controls, then return to details; app-owned dismissal is wired
through the native player delegate. Device focus restoration is still a runtime
verification requirement, not a compiler guarantee.

## Screening Deck Presentation

`TVDeckStyle.swift` owns the TV adaptation of the Mac screening deck: a metal-blue
gradient and static star/grid background, ruled headings, metal-blue library bays, and panoramic
viewport edges with illuminated corner brackets. Home puts a quiet Screening Deck header and profile label above a 660-point
framed hero, leaving room for shelves below. The hero has a native Liquid Glass
information panel, system typography, native glass Play/Resume, Details and pager
buttons. The pager sits at the upper trailing edge with a real item index; it
does not compete with Play/Details in the information panel. Artwork cards have fine neutral edges and retain native card focus.
Details use a wide backdrop/title/summary viewport instead of an extra poster.
Search, library grids and Show All use the same background and shelf treatment;
Settings and playback options retain their native form surfaces.

Keep native top tabs and persistent navigation stacks on TV. The Mac's bottom
pointer-driven instrument console is not the TV navigation control. Decoration
is static, noninteractive and hidden from accessibility; no continuous drawing
loop, decorative telemetry or additional artwork request is introduced. Reduce
Transparency makes hero panels and shelf bays opaque and uses bordered action
buttons. Existing Reduce Motion
handling continues to disable hero transitions and rotation.

The 2026-10-25 styling checkpoint passed signed Mac and TV builds and the platform
boundary gate, and was installed on the user's Apple TV. The user confirmed that
the UI visually looks good. This is appearance approval, not a separate
confirmation of focus or playback behavior. Agents did not launch either app or
run tests.

## App Icon

The TV icon reuses the Cinerama West Coast glass C from the Mac Icon Composer
source, centered on a midnight-blue gradient matching the Mac composition.
Sunset coral/amber and Pacific teal/blue are confined to the brand mark; see
[icon design](icon-design.md) for the master and generation prompt.
Foreground and background remain separate native TV parallax layers. Do not
bake a rounded mask or a second square Mac icon inside the TV tile.

Run `swift scripts/generate_tvos_icon.swift` after changing the Mac logo source.
It packages the existing artwork into 400 × 240 (1×/2×) Home Screen and
1280 × 768 App Store stacks under `CineramaTV/Resources/Assets.xcassets/TVIcon.brandassets`.
The generated PNGs are committed; the unmasked review preview stays in `.build/`.
The script does not alter Mac icon assets or require them in the TV app bundle.

## Details and Playback

Details are an artwork-led viewport with title, year and summary. A prominent
Play/Resume action uses the first locally supported version and remembered
tracks, using the same resolver eligibility checks as explicit playback options.
A separate Playback Options route holds the native version/audio/subtitle form
and Play from Start. Show seasons use poster grids; season episodes use landscape
artwork grids, both preserving server-scoped navigation and native card focus. Unsupported tracks remain explanatory text rather than selectable
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

Caption appearance has no Cinerama picker. `TVSystemCaptionStyle` translates the
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

`CineramaTVTests` runs against the actual TV module on the paired Apple TV HD.
Resolver/copy-only policies, semantic track persistence, terminal playback
cleanup, native Back delegation and selected shared library/data contracts have
automated coverage. See [Automated testing](testing.md) for signed commands and
the current passing baseline. This does not validate focus traversal or captions
visually.

Run both signed builds and the generated-project platform-boundary check.
The build scripts run this structural check automatically after XcodeGen.
Install the signed TV build on Apple TV HD for user verification. Agents run automated tests; manual app launches and visual inspection are
left to the user. Verify Home/library
browsing, search, focus/Back, paging, direct/remux playback, audio/subtitles,
remembered Off across episodes/profiles, system captions, progress/resume and
completion. Mac visuals/input need their own authorized runtime check.

## Cross-Platform Theme Updates

Visual changes apply to both platforms by default, through separate UI
implementations. `TVDeckPalette` mirrors the Mac background `#1D2D40`, surface
`#2D455F` and secondary text `#B2C5D9` tokens. Update both palettes together.
`TVDeckActionStyle` uses native `.glass`/`.glassProminent` buttons, preserving
remote focus, activation and accessibility. Home Search/Refresh/Show All, hero
actions/pagers and detail playback actions use these styles. Native TV tabs,
forms and AVKit controls retain platform ownership; media cards retain `.card`.

TV uses fullscreen metal-blue architecture and glass over title artwork in place
of Mac desktop/window translucency. Do not add AppKit window effects or backdrop
blur to every shelf/card on Apple TV HD. `TVDeckInformationPanel` owns the single
hero glass panel; Reduce Transparency uses an opaque blue fill. The app root
also supplies the metal-blue background for linking/profile screens. No new
artwork requests, animation loops or playback changes are introduced.

The metal-blue/Liquid Glass update passed both signed builds and platform-boundary
checks. It requires a fresh user visual/focus check; the earlier appearance
approval applies to the preceding screening-deck version. Agents did not launch
either app or run tests.

The [experimental Live TV tab](tvos-live-tv.md) now offers HD MPEG-2
CPU path with TV-owned remote controls and a red LIVE marker. Library
AVKit behavior remains independent. No Go Live, DVR or Live TV captions are added.

## TV UX refinement (2026-10-27)

The TV-only refinement keeps the Mac palette, static screening-deck architecture,
28-point surfaces and neutral native glass actions. It adapts the presentation
for viewing distance and remote input, following Apple's
[tvOS layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout).
Native tabs and separate navigation stacks remain mounted. Home/shelf focus
sections group related actions without intercepting Back or forcing focus away
from a returning card. Two-line media titles reserve consistent label height.
Channel logos use aspect-fit artwork; a search with no matching channels has an
explicit empty state. Browsing copy describes the task rather than decoder
implementation details. Linking uses a centered information panel; profile locks
use native symbols. Settings retains native forms and removes appearance prose
that wasn't a setting.

Live TV has a compact neutral-black control panel with Play/Pause, Audio and
More. It hides after five seconds of playing without navigation/action changes;
remote direction or Select restores it, and remote Play/Pause works while hidden.
Paused, tuning, error, audio/More/information presentations and VoiceOver keep
controls visible. Hidden controls hand focus to an invisible, labeled surface
button; restoring them returns focus to Play/Pause. Reduce Motion disables the
fade and Reduce Transparency makes the panel opaque. Back still returns directly
to channels. Library transport remains owned by AVKit.

Manual visual inspection is user-owned. Check safe-area edges, long titles,
hero action fit, card expansion, directional focus between shelves, return from
Playback Options/player, and Live TV control reveal/audio/More/Back on Apple TV HD.
Hosted tests and signed builds do not establish these visual/focus properties.

Verification for this refinement: both Apple Development-signed builds and all
40 TV hosted tests pass on the tvOS 26.0 simulator and Apple TV HD/tvOS 26.6.
The signed TV update was installed without a manual launch. Source boundaries
and diff checks pass. Mac UI/shared playback source is unchanged; its preceding
186-test baseline remains the latest full Mac test run. The existing TV tests
cover playback policy, lifecycle, native renderer and modal contracts; the new
visual hierarchy, control fade and remote focus paths still need user acceptance.
