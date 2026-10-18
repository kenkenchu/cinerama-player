# Apple TV Feasibility Prototype

`Dusk-tvOS` is an experimental device target for Apple TV HD, tvOS 26+.
The Mac target remains the supported full app. Read [the design](tvos-design.md)
for platform boundaries and [the workflow](development-workflow.md) for the
required separate signed Mac build.

## Implemented Scope

The prototype shares PlexService, server-scoped models, Keychain auth, profile
bootstrap/switching, discovery/recovery, metadata and copy-only playback APIs.
TV UI lives exclusively in `DuskTV/Sources`, outside the Mac source tree.
`project.yml` explicitly selects TV shared sources; no Mac app/feature views,
AppKit player hosts, desktop VLC or DuskDovi compile into the TV app.

TV has link-code sign-in, protected Plex Home profile selection, Continue
Watching, paged video libraries, show/season/episode navigation, media-version
selection, start/resume, native AVKit remote controls, and Plex timeline reports
at startup, approximately every ten seconds and on dismissal. Returning to the
item refreshes metadata. The Last playback section shows the delivery route
and progress-sync status without exposing URLs or credentials.

`TVStreamResolver` conservatively permits HD SDR H.264/HEVC and locally
compatible audio. Version buttons identify the chosen audio; when the default
track is incompatible, a compatible alternative is named on the button.
`TVPlaybackCoordinator` manages AVPlayer, audio-session activation, direct play,
copy-only fragmented-MP4 HLS for other containers/track choices, one HLS fallback
on direct failure, timeline reporting and remux cleanup. HLS never starts without
Plex confirming both video and audio copying. Plex decision failure does not
permit conversion. App backgrounding pauses playback.

Subtitles start Off; AVKit exposes supported embedded tracks. External sidecars,
Plex subtitle-choice persistence, full audio-track mapping, VLC, Live TV,
autoplay, downloads, enhancement and HDR conversion are outside this prototype.
Browsing uses native text lists to establish feasibility before artwork/layout
work. TV-only layered app icon assets provide a black DUSK Home Screen tile. There is no Top Shelf extension or App Store distribution setup.

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
   and `xcodebuild -project Dusk.xcodeproj -scheme Dusk-tvOS -showdestinations`
   (build destination ID). These may use different identifiers for the same TV.
5. Build with your team ID, optionally specifying the Xcode destination ID to
   register the connected device and generate its development profile:

   ```bash
   DUSK_TVOS_TEAM=YOUR_TEAM_ID DUSK_TVOS_DEVICE_ID=YOUR_XCODE_DESTINATION_ID \
     ./scripts/build_tvos.sh
   ```

6. Install the signed result without launching it:

   ```bash
   xcrun devicectl device install app --device YOUR_DEVICECTL_ID \
     .build/tvos/DerivedData/Build/Products/Debug-appletvos/DuskTV.app
   ```

The script requests automatic development provisioning, verifies the signed
bundle and embedded profile, and never launches the app. An unsigned compiler
check is not an installable deliverable. If Apple reports no registered devices
or no profile, complete pairing/registration and rerun the signed build. Do not
fall back to ad hoc signing. No private keys, profiles or build products belong
in Git. TV provisioning is separate from the existing Mac signing workflow.

## User End-to-End Check

1. Open Dusk Prototype on Apple TV and allow Local Network access if requested.
2. Enter the displayed code at `plex.tv/link` on your phone/computer, then choose
   your Plex Home profile (including its PIN if protected).
3. Confirm accessible servers' video libraries appear. An unavailable server
   should not hide working libraries; Refresh Servers retries discovery.
4. Open a known 720p/1080p SDR H.264 movie, preferably MP4 with AAC/AC3, and play.
   Check video, audio, remote play/pause, seeking and Back. Back may first hide
   the native player controls; another Back returns to the item.
5. After at least 20 seconds, return to details. Check Last playback for progress
   sync, verify progress in Plex, then Resume and check the position.
6. Repeat with an HD MKV using compatible audio. Last playback should report
   Direct Stream with both tracks copied; Plex Dashboard can independently
   confirm there was no A/V encoding.
7. Browse a show → season → episode and repeat. Try native embedded subtitles,
   background/return, and a few minutes of sustained playback.
8. Record title, version, codecs, route, symptom and whether progress persisted
   for failures. Do not share tokens or raw media/artwork URLs.

Successful compilation does not establish device playback, focus restoration,
subtitle compatibility, sustained A8 performance or unchanged Mac visuals.
Mac runtime verification remains a separate explicitly authorized check.

## Initial Build Verification

On 2026-10-17, the Apple Development-signed Mac build and signed tvOS device
build passed using Xcode 27.1. The TV app installed successfully on the user's
Apple TV HD (AppleTV5,3), running tvOS 26.6 with Developer Mode enabled.
Agents did not launch either app or run tests. End-to-end Plex sign-in,
playback, remote interaction and progress sync remain for user verification.
Source-membership inspection confirmed no TV UI in the Mac compilation and no
Mac UI/player hosts in TV. Extracted shared cache and quality-preset definitions
were checked against their original implementations without behavioral edits.

If installation succeeds but the tile is missing, verify the app appears in
`devicectl device info apps` and is not hidden. The TV asset catalog must be
compiled with `ASSETCATALOG_COMPILER_APPICON_NAME=TVIcon`; the built Info.plist
should contain `CFBundleIcons.CFBundlePrimaryIcon`. If registration is correct
but the Home Screen is stale, restart Apple TV via Settings → System → Restart.
The initial icon follow-up rebuilt/reinstalled successfully and verified app
registration as not hidden; Home Screen appearance remains user-verified.
