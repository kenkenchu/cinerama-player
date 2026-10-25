# Cinerama for Mac and Apple TV

Formerly Dusk Player. Native **macOS and tvOS Plex clients**, maintained in
[kenkenchu/dusk-player-mac](https://github.com/kenkenchu/dusk-player-mac), forked
from [marvinvr/dusk-player](https://github.com/marvinvr/dusk-player).

This repository targets the user's **Apple silicon Mac on macOS 26+** and
**Apple TV HD (A8) on tvOS 26+**, currently running tvOS 26.6. The platforms share
Plex models/services while keeping their native interfaces and rendering hosts
separate. TV feature coverage is growing from user-confirmed basic playback and
text subtitles; full Mac feature parity is not implied.

## Library Playback

Both clients link to Plex, support Plex Home profiles and server-scoped media,
and use original-quality direct playback or confirmed copy-only HLS remuxes.
**Server video/audio re-encoding is prohibited.** Unsupported formats explain
the limitation rather than silently asking Plex to convert them.

The TV client includes a cinematic Continue Watching hero, Mac-equivalent
library Home shelves/recommendations/actions, artwork-based library browsing,
search, movie/show/episode details, compatible audio and text subtitles, resume,
and Plex watch-state reporting. Audio/subtitle choices are remembered per
profile/server/movie or series. Native AVKit supplies remote transport controls;
caption styling derives from Apple TV accessibility preferences. New UI,
preference, caption-style and lifecycle changes require device verification.
**4K/UHD is rejected on Apple TV HD**, with an informational message and other
HD versions offered when available. No local 4K downscaling is planned.

The Mac app additionally offers desktop VLCKit, intro/credits skipping,
continuous play, downloads/offline sync, Live TV channel browsing/playback,
optional Seerr requests, native window/fullscreen and keyboard/pointer controls,
and supported Metal/HDR/Dolby Vision paths. These Mac capabilities remain intact.
TV Live TV, VLC and continuous play are later milestones. There is no App Store
release or iOS target for this fork.

## Build and Install

Install Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and
[rustup](https://rustup.rs) for the Mac converter. Open Xcode once to finish setup.

For Mac, use the installed Apple Development identity consistently:

```bash
security find-identity -v -p codesigning
DUSK_MACOS_SIGNING_IDENTITY='YOUR_APPLE_DEVELOPMENT_IDENTITY' ./scripts/build_macos.sh
```

The script fetches checksum-pinned desktop VLCKit, builds DuskDovi, generates the
project, checks platform source boundaries, builds and verifies nested signatures.
Output: `.build/macos/DerivedData/Build/Products/Debug/Cinerama.app`.
Do not silently fall back to ad hoc signing on this workstation. Allow Local
Network access in System Settings so the app can reach local Plex servers.

For Apple TV, pair the device in Xcode, then:

```bash
DUSK_TVOS_TEAM=YOUR_TEAM_ID DUSK_TVOS_DEVICE_ID=YOUR_XCODE_DESTINATION_ID \
  ./scripts/build_tvos.sh
xcrun devicectl device install app --device YOUR_DEVICECTL_ID \
  .build/tvos/DerivedData/Build/Products/Debug-appletvos/Cinerama.app
```

Open **Dusk** on the TV, permit Local Network access and link at `plex.tv/link`.
See [TV device workflow](docs/tvos-prototype.md) for provisioning and verification.
Build scripts never launch either app or run tests.

## Development

See [documentation](docs/README.md), [workflow](docs/development-workflow.md),
[Mac style](STYLE.md), [TV design](docs/tvos-design.md) and [TV UI](docs/tvos-ui.md).
`project.yml` is authoritative; XcodeGen generates the project. Both build
scripts enforce UI/dependency separation with
`scripts/verify_platform_boundaries.py`. Preserve Mac signing, input and layout
when changing shared logic. Report fork issues in
[this repository](https://github.com/kenkenchu/dusk-player-mac/issues).

## License

Dusk is released under the [MIT License](LICENSE). Upstream attribution and
license notices are preserved.

Mac playback uses desktop [VLCKit](https://code.videolan.org/videolan/VLCKit),
licensed under LGPL v2.1 and linked dynamically. Dolby Vision profile 7 conversion
uses quietvoid's MIT-licensed `dolby_vision` crate and its MIT-compatible
dependencies, linked statically. Notices ship in
[Dusk/Resources/ThirdPartyNotices.txt](Dusk/Resources/ThirdPartyNotices.txt).
TV currently uses system frameworks only. Dusk is not affiliated with or
certified by Plex or Dolby Laboratories.
