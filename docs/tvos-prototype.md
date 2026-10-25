# Apple TV Build, Install and Verification

`Cinerama-tvOS` is maintained alongside `Cinerama-macOS` for Apple TV HD, tvOS 26+.
Library playback is the first TV milestone; Mac and TV have different coverage. Read [the design](tvos-design.md)
for platform boundaries and [the workflow](development-workflow.md) for the
required separate signed Mac build.

## Implemented Scope

The maintained TV library client shares PlexService, server-scoped models,
Keychain auth, Plex Home profiles, discovery/recovery, artwork, account library
order, merge functions and copy-only Plex playback APIs. TV UI lives exclusively
in `CineramaTV/Sources`, outside the Mac tree. No Mac views, AppKit player hosts,
desktop VLC or CineramaDovi compile into TV; build scripts enforce these boundaries.

Home, Libraries, Search and Settings have separate navigation stacks. Home now
shares the Mac Home model and presents a cinematic Continue Watching hero,
library-ordered Plex hubs, personalized genre shelves, watched actions and Show
All. See [TV Home](tvos-home.md) for the library feature mapping; Live TV remains
deferred. Libraries
use paged artwork grids in account order; search fans out across connected
servers. Profile switches invalidate old results; catalog refresh preserves the
shell and reports outages per server. Details show artwork, metadata, hierarchy,
media versions and compatible audio/text-subtitle selectors.

`TVStreamResolver` permits compatible HD SDR H.264/HEVC and audio, rejects
4K/UHD with an informational message, and refuses unsupported HDR/codecs. No
software downscaling or server re-encoding is planned. `TVPlaybackCoordinator`
starts direct where possible, uses copy-only fragmented-MP4 HLS for containers/
track choices that need it, and allows one HLS fallback on direct failure. Both
video and audio must be confirmed copied before HLS starts.

Text subtitles (including sidecars) are selected on the title page, recorded on
Plex's part and requested by ID for segmented WebVTT delivery. Select the unique
received AVPlayer legible track without gating video startup on subtitle
metadata. SRT/WebVTT and ASS/SSA text packaging is allowed; advanced ASS styling
and bitmap subtitles are not supported. Device-local audio/subtitle preferences
are scoped by profile/server/movie or series and include explicit subtitle Off.
Changes take effect on the next Play/Resume. Native AVKit also exposes received
tracks during playback; complete persistence of in-player native-menu changes
is not yet implemented.

The display name is Cinerama. The new bundle identifier is
`com.cinerama-player.tv`; the renamed app requires a new installation and Plex
linking. Native AVKit supplies remote transport controls. Explicit system caption
appearance overrides are adapted into WebVTT style rules and refreshed on
settings/foreground changes; no Cinerama appearance preferences exist. The adapter
requires user visual verification. Timeline requests are serialized, include
transport changes, periodic progress and final stopped state. Natural completion
marks the item watched. Catalog refresh waits for final progress/remux cleanup.

TV Live TV, VLC, automatic next episode, downloads, enhancement and HDR
conversion are deferred. No Top Shelf extension or App Store workflow is added.
See [TV UI](tvos-ui.md) for current implementation boundaries and runtime checks.

## Pair, Build and Install

1. Put Mac and Apple TV on the same network. On Apple TV, leave Settings →
   Remotes and Devices → Remote App and Devices open.
2. In Xcode choose Window → Devices and Simulators (Shift-Command-2), select
   Devices, select the discovered Apple TV, and Pair using the TV's displayed
   code. Apple TV HD can also connect by a USB-C data cable.
3. Ensure your Apple account/team is available in Xcode Settings → Accounts.
   Enable Developer Mode on Apple TV if Xcode or the device requests it, then
   follow its restart/confirmation prompts.
4. Find the paired device with `xcrun devicectl list devices` (installation ID)
   and `xcodebuild -project Cinerama.xcodeproj -scheme Cinerama-tvOS -showdestinations`
   (build destination ID). These may use different identifiers for the same TV.
5. Build with your team ID, optionally specifying the Xcode destination ID to
   register the connected device and generate its development profile:

   ```bash
   CINERAMA_TVOS_TEAM=YOUR_TEAM_ID CINERAMA_TVOS_DEVICE_ID=YOUR_XCODE_DESTINATION_ID \
     ./scripts/build_tvos.sh
   ```

6. Install the signed result without launching it:

   ```bash
   xcrun devicectl device install app --device YOUR_DEVICECTL_ID \
     .build/tvos/DerivedData/Build/Products/Debug-appletvos/Cinerama.app
   ```

The script requests automatic development provisioning, verifies the signed
bundle and embedded profile, and never launches the app. An unsigned compiler
check is not an installable deliverable. If Apple reports no registered devices
or no profile, complete pairing/registration and rerun the signed build. Do not
fall back to ad hoc signing. No private keys, profiles or build products belong
in Git. TV provisioning is separate from the existing Mac signing workflow.

## Verified Workstation and Device (2026-10-25)

The signed build and installation succeeded with:

- Development team: `JCJFCBSNUG` (certificate subject `OU`).
- Signing identity: `Apple Development: kenkenchu@gmail.com (BZ2K63HJTE)`.
  `BZ2K63HJTE` is the identity suffix, **not** the development team ID; using it
  as `CINERAMA_TVOS_TEAM` fails provisioning.
- Connected device: `Apple TV 4th`, Apple TV HD (`AppleTV5,3`).
- Xcode destination and devicectl installation ID (both verified):
  `c8b3bc526b697182f0646a639aef4be26f1ca852`.

From the repository root, build and install with:

```bash
CINERAMA_TVOS_TEAM=JCJFCBSNUG \
  CINERAMA_TVOS_DEVICE_ID=c8b3bc526b697182f0646a639aef4be26f1ca852 \
  ./scripts/build_tvos.sh
xcrun devicectl device install app \
  --device c8b3bc526b697182f0646a639aef4be26f1ca852 \
  .build/tvos/DerivedData/Build/Products/Debug-appletvos/Cinerama.app
```

Confirm the device is connected with `xcrun devicectl list devices` before
installing. If pairing or identifiers change, rediscover both IDs as described
above. The installed bundle is `com.cinerama-player.tv`. This checkpoint verified
the signed build and installation only; the app was not launched and tests were
not run.

## Automated Tests

The `Cinerama-tvOS` scheme now includes the hosted `CineramaTVTests` target.
Run `scripts/test_tvos.sh` for the local tvOS 26 simulator. With the verified
team/device variables above, the same command explicitly runs on Apple TV HD.
The 32-test TV suite passed on this Apple TV HD; the Mac suite passed all 178
tests. See [Automated testing](testing.md) for coverage, signing and limitations.
Tests run through Xcode without manual visual inspection or actual media playback.

## User End-to-End Check

1. Open Cinerama on Apple TV and allow Local Network access if requested.
2. Enter the displayed code at `plex.tv/link` on your phone/computer, then choose
   your Plex Home profile (including its PIN if protected).
3. Confirm accessible servers' video libraries appear. An unavailable server
   should not hide working libraries; Refresh Servers retries discovery.
4. Open a known 720p/1080p SDR H.264 movie, preferably MP4 with AAC/AC3, and play.
   Check video, audio, remote play/pause, seeking and Back. Back may first hide
   the native player controls; another Back returns to the item.
5. After at least 20 seconds, return to details. Open Playback Information to check progress
   sync, verify progress in Plex, then Resume and check the position.
6. Repeat with an HD MKV using compatible audio. Playback Information should report
   Direct Stream with both tracks copied; Plex Dashboard can independently
   confirm there was no A/V encoding.
7. Browse a show → season → episode and repeat. Choose a named text subtitle
   on its title page before Play/Resume and check rendering and Off. Also try
   background/return, and a few minutes of sustained playback.
8. Record title, version, codecs, route, symptom and whether progress persisted
   for failures. Do not share tokens or raw media/artwork URLs.

Successful compilation does not establish device playback, focus restoration,
subtitle compatibility, sustained A8 performance or unchanged Mac visuals.
Mac runtime verification remains a separate explicitly authorized check.

## Current Verification Status

The user authorized maintaining both targets after confirming feasibility,
prioritizing TV library playback and deferring Live TV. The artwork tab shell,
search, semantic track preferences, system caption adapter and revised timeline
lifecycle passed signed Mac/TV builds and were installed for user device
verification. The platform-boundary gate passed; Mac UI sources were untouched. The project-wide rename now uses `com.cinerama-player.tv`, a separate installed
app and storage identity requiring Plex linking again. Historical device
confirmations below predate that identity change.
The user subsequently confirmed library artwork and selecting videos to play.
Home-specific hero, recommendation, menu and focus changes still need user
verification. Neither app was launched by agents and no tests were run.

## Initial Build Verification

On 2026-10-17, the Apple Development-signed Mac build and signed tvOS device
build passed using Xcode 27.1. The TV app installed successfully on the user's
Apple TV HD (AppleTV5,3), running tvOS 26.6 with Developer Mode enabled.
Agents did not launch either app or run tests. The user subsequently confirmed
the Home Screen icon appeared without restarting, Plex linking succeeded and
basic playback worked. Subtitles did not render despite native On/Off/CC menu
options; source format was not established. After explicit Plex text-track
selection and remux mapping were added, the user confirmed subtitles render.
The user reports they do not yet follow system caption styling; that is an open
TV issue. This confirms the exercised subtitle path only. Broader remote
interaction, progress sync, subtitle formats and style coverage remain unverified.
Source-membership inspection confirmed no TV UI in the Mac compilation and no
Mac UI/player hosts in TV. Extracted shared cache and quality-preset definitions
were checked against their original implementations without behavioral edits.

If installation succeeds but the tile is missing, verify the app appears in
`devicectl device info apps` and is not hidden. The TV asset catalog must be
compiled with `ASSETCATALOG_COMPILER_APPICON_NAME=TVIcon`; the built Info.plist
should contain `CFBundleIcons.CFBundlePrimaryIcon`. If registration is correct
but the Home Screen is stale, restart Apple TV via Settings → System → Restart.
The initial icon follow-up rebuilt/reinstalled successfully and verified app
registration as not hidden; the user subsequently confirmed the icon appeared
without a restart. The current icon uses Cinerama's sunset-and-Pacific glass C on a midnight-blue
layered background; see [TV UI](tvos-ui.md) and [icon design](icon-design.md).
