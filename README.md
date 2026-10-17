# Dusk Player for Mac

A native **macOS-only Plex client**, maintained in
[kenkenchu/dusk-player-mac](https://github.com/kenkenchu/dusk-player-mac), forked
from [marvinvr/dusk-player](https://github.com/marvinvr/dusk-player).

Dusk uses SwiftUI and AppKit to browse and play your Plex libraries in a Mac
window. This fork supports **Apple silicon Macs running macOS 26 or later**.

## Features

- Plex sign-in and Plex Home profiles.
- Home recommendations, library browsing, search, and media details.
- Direct playback through AVPlayer and desktop VLCKit, including MKV support.
- Audio/subtitle selection and per-session manual playback quality.
- Resume, watched-state reporting, intro/credits skipping, and continuous play.
- Downloads, offline playback, and delayed watch-state synchronization.
- Plex Live TV guide and playback, plus optional Seerr requests.
- Native sidebar navigation, resizable window, fullscreen, and keyboard controls.
- AVPlayer Metal enhancement and HDR/Dolby Vision remux/conversion paths;
  output depends on the media, Mac, display, audio route, and Plex server.

The Mac UI currently has no Picture in Picture, AirPlay route picker, outgoing
SharePlay invitation controls, system media-key integration, in-app purchases,
or alternate app icon picker. Siri/Shortcuts integration is inherited but is
not a verified Mac feature. There is no App Store release for this fork.

Report fork-specific issues in
[this repository](https://github.com/kenkenchu/dusk-player-mac/issues).

## Build

Install Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and
[rustup](https://rustup.rs). Open Xcode once to finish setup, then:

```bash
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain
./scripts/build_macos.sh
```

The script downloads checksum-pinned desktop VLCKit, builds the native DuskDovi
converter, generates the Xcode project, builds `Dusk-macOS`, and verifies its
local signature. It never launches the app or runs tests.

The app is at `.build/macos/DerivedData/Build/Products/Debug/Dusk.app`.
You can also open `Dusk.xcodeproj` and select **Dusk-macOS → My Mac**.
Set `DUSK_MACOS_SIGNING_IDENTITY` to an installed Apple-issued signing identity
if available; local builds otherwise use ad hoc signing. Distribution signing
and notarization are separate.

Allow Dusk in **System Settings → Privacy & Security → Local Network** so it can
reach local Plex servers. If sign-in succeeds but Home times out, check that
permission and use the signed app produced by the build script.

## Development

See [the documentation index](docs/README.md),
[Mac build workflow](docs/development-workflow.md), and [design system](STYLE.md).
`origin` points to this fork; `upstream` points to the original project. Only
macOS targets, desktop dependencies, and Mac verification are maintained here.

## License

Dusk is released under the [MIT License](LICENSE). Upstream attribution and
license notices are preserved.

Playback uses desktop [VLCKit](https://code.videolan.org/videolan/VLCKit),
licensed separately under LGPL v2.1 and linked dynamically. Dolby Vision profile
7 conversion uses quietvoid's MIT-licensed `dolby_vision` crate and its
MIT-compatible dependencies, linked statically. Their notices ship in
[Dusk/Resources/ThirdPartyNotices.txt](Dusk/Resources/ThirdPartyNotices.txt).
Dusk is not affiliated with or certified by Plex or Dolby Laboratories.
