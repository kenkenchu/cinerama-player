# TV Home — Library Feature Parity

The TV Home screen shares Mac Home's data/behavior layer while owning its own
remote-first presentation. Live TV remains deferred by user instruction; this
milestone covers **library Home**, not full platform/player feature parity.
Mac windows, pointer/keyboard behavior and rendering hosts remain separate.

## Feature Mapping

| Mac Home feature | TV implementation |
| --- | --- |
| Cinematic Continue Watching hero | Backdrop, Plex title logo or title text, episode title, metadata, summary and Play/Resume with watched-fraction fill. Details and bounded pager controls use native remote focus. |
| Hero rotation/navigation | Seven-second rotation, Previous/Next controls and position indicator. Rotation stops while actions have focus, playback is preparing/presented, another route/tab is active, the app is inactive, or Reduce Motion is enabled. |
| Filtered, library-ordered Plex hubs | The same `HomeHubFilter`, `HomeHubArrangement` and account library order. Hide duplicate Continue Watching/On Deck and playlist hubs. |
| Recently Added | Same 15-item inline limit, background expansion and actual show metadata normalization, including Show All. |
| Personalized genre shelves | Same `HomeRecommendationEngine`, viewing-history scoring, daily candidate selection and exclusions for completed/in-progress titles. No fabricated rows when history/candidates are insufficient. TV Settings exposes Personalized Shelves. |
| Show All | Merged hub source expansion through `HomeHubItemsViewModel`; personalized single-library genre navigation through `LibraryItemsViewModel` with the same local genre matching. As on Mac, a multi-library personalized shelf has no single-library Show All route. |
| Explicit watched actions | Long-press cards or the hero Play/Resume button for Mark Watched/Unwatched, using known cross-server copies. Hero also offers Remove from Continue Watching. |
| Detail/hierarchy navigation | View Details, Go to Season and Go to Show, carrying the item's own server-scoped identity. |
| Artwork/labels/progress | Shared Plex presentation/formatting; 2:3 posters, 16:9 clip rows, watched checks and partial-progress bars. |
| Refresh and error states | Refresh button, tab/scene return, player dismissal and server-content changes. Reuse first-paint settling, remembered hero sources, retained payloads during request failures, partial-outage notes and empty/error states. |
| Home search action | Search button selects the native Search tab. |
| Live TV shelf | Deferred with TV Live TV support; no guide/channel placeholder is presented as working tuning. |

## Ownership

- `CineramaTV/Sources/TVHomeView.swift`: Home navigation stack, composition,
  contextual actions, availability notes and lifecycle hooks.
- `TVHomeHero.swift`: TV backdrop/title/action/pager presentation and focus-aware
  rotation. Only the next backdrop is prefetched into the bounded artwork cache.
- `TVDeckStyle.swift`: TV-owned screening-deck background, library bays, ruled
  headings and illuminated viewport edges, matching the Mac visual language
  while preserving native TV tabs and card focus. See [TV UI](tvos-ui.md).
- `TVHomePlaybackModel.swift`: resolve fresh server-bound metadata and a locally
  supported media version for direct hero Play/Resume. Reuse remembered audio/
  subtitle choices. Resolve a defensive show/season input to an episode.
- `TVHomeGrids.swift`: TV Show All/genre layouts over shared data models.
- `TVAppModel`: owns one shared `HomeViewModel` for the account lifetime,
  connection refresh, TV Home preferences and profile/session invalidation.
- Shared `Features/Home` view models, recommendation/filter/order/first-paint
  helpers, genre matching, presentation/formatting and watched fan-out methods
  are explicitly included in the TV target. Mac views are not.

`LibraryGenreOption` and `PlexLibrary`'s server-scoped Hashable conformance live
with models rather than Mac views. Watched-action availability lives in the
shared Plex presentation helper. Mac-only `showAllRoute` stays in
`HomeViewModel+MacNavigation.swift`; TV routes do not import `AppNavigation`.
The platform-boundary build gate explicitly allows the data files while
rejecting Mac view files and the Mac navigation adapter in TV.

## Session and Playback Invariants

Cancel the shared model's account-owned work before TV profile switching or
sign-out, and clear its payloads on a successful switch. Async Home loads,
recommendation publication, expansion, account-identity reads and watched
fan-out must not publish or mutate another Plex profile's session.

The hero modal is above the entire Home navigation stack. On dismissal, await
final progress/remux cleanup before notifying catalog refresh; do not let the
Home appearance callback race that finalization. Restore the first hero after
player/scene/tab return. Keep the catalog mounted during ordinary refreshes.

Hero playback uses `TVStreamResolver.preferredChoice`; unsupported 4K/HDR or
codec-only versions produce an informational error, never a downscale or a
server re-encode. A compatible HD version may still play. Selecting Details
allows explicit version and track choices. This does not constrain Mac routing.

## Verification

Both signed builds and the generated-project boundary check are required.
Moved model/conformance/availability/navigation definitions were compared with
their originals to preserve Mac behavior. Agents do not launch either app or
run tests without explicit authorization.

On the Apple TV HD, verify:

1. In-progress media appear in the hero with correct series/episode labels,
   artwork and progress. Previous/Next, Details and Play/Resume work.
2. Remote focus stays predictable while paging; a focused action never changes
   title automatically. Back restores the Home route after playback.
3. Recently Added TV uses show posters/details; Show All includes every source.
   Clip-only rows use landscape artwork and date/duration labels.
4. Long-press watched/unwatched/removal actions reconcile with Plex and known
   alternate copies. Season/show links stay on their originating server.
5. Personalized shelves appear only with sufficient history/candidates. Toggle
   them in Settings and verify Continue Watching/completed titles are excluded.
6. Return from playback, another tab and background; refresh should preserve
   navigation and avoid replacing the page with a partial merge.
7. An unavailable server does not hide working ones. Profile switches show no
   previous profile's shelves, and 4K-only playback is rejected clearly.

Compiler success is not a claim that focus, artwork composition or all server
payloads have been runtime-verified. The user verifies these on the device.
