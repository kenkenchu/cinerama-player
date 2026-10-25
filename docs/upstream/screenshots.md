> Archived original-project reference. Names and paths were normalized during
> the Cinerama rename; this is not an active feature or build specification.
> See the root README for original-project credit.

> Historical upstream reference. This fork supports native macOS only.
> These platform-specific instructions are not maintenance or verification requirements.

# App Store Screenshots

The App Store screenshots live in `screenshots/<version>/` (`iphone-6.9`,
`ipad-13`, `appletv`). They are rendered by a separate, private tool that
builds this repo's Debug app, captures it in the simulators against a local
demo Plex server and composes the marketing panels; it writes its output back
into `screenshots/<version>/`. The demo library shows metadata and cover art
of real titles only; the player shows neutral public-domain frames, never
scenes from those titles.

## App side: DEBUG screenshot mode

`Cinerama/Sources/App/ScreenshotMode.swift` is the only part of the pipeline in
this repo. It is compiled out of Release builds (`#if DEBUG`) and driven purely
by launch arguments:

| Argument | Effect |
| --- | --- |
| `-CineramaScreenshotMode YES` | Signs in with a fake account token (Keychain untouched); hero rotation off |
| `-CineramaScreenshotPlexTV <url>` | Replaces `https://plex.tv` (`PlexService.plexTVBase`) |
| `-CineramaScreenshotScreen <name>` | `home`, `movies`, `shows`, `library`, `detail`, `search`, `player`, `downloads`, `settings`, `serverPriority`, `supporter`, `icons` |
| `-CineramaScreenshotItem <ratingKey>` / `-CineramaScreenshotItemType <type>` | Item for `detail`/`player`; type also picks the `library` tab |
| `-CineramaScreenshotPlayOffset <seconds>` | Exact player start position, ignoring the resume point |
| `-CineramaScreenshotKeepHUD YES` | Player controls never auto-hide |
| `-CineramaScreenshotSearch <query>` | Pre-filled search |
| `-CineramaScreenshotDownloads movie:<rk>,episode:<rk>` | Queues real downloads |
| `-CineramaScreenshotSeedDownloads movie:<rk>,season:<rk>` | Records finished downloads (metadata and artwork through the normal cache path, a sparse placeholder file); `season:` expands to its episodes |
| `-CineramaScreenshotSeerr <url>` | Acts as signed in to a demo Seerr at that URL (Keychain untouched) |
| `-CineramaScreenshotPlayerSheet audio\|subtitles` | iOS player: opens that picker once the tracks are in and keeps it open |
| `-CineramaScreenshotUpNext <seconds>` | Episode player shot: raises the full-screen Up Next for the next episode; every Up Next countdown stops at that many seconds |
| `-CineramaScreenshotHeroIndex <n>` | iOS/iPadOS Home hero opens on item `n` instead of the first (rotation is off in screenshot mode) |
| `-CineramaScreenshotTVInputs "wait:3500,up,panel:subtitles"` | tvOS player: synthetic Siri Remote input (`pan:<points>` leaves the play bar scrubbing) |

Hooks: `PlexService` (plex.tv base + token), `MainTabView` (routing + sheet),
`AppNavigationRoute.screenshotServerPriority`, `SearchView` (query),
`PlayerViewModel` (HUD auto-hide), `PlaybackCoordinator.playForScreenshot`
(exact start, forced Up Next), `PlaybackCoordinator+UpNext` (frozen
countdowns), `PlayerView` (tvOS input replay, iOS picker),
`DownloadManager.seedCompletedDownloadForScreenshot`, `SeerrService` (demo
session), `HomeCinematicHero` (rotation).

When changing routing, sign-in, the player HUD or Home loading, keep these
hooks compiling and behaving; a broken hook only shows up when screenshots are
regenerated.
