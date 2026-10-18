# Product and Scope

## Product Shape

Dusk Player for Mac is a native SwiftUI/AppKit Plex client maintained in
`kenkenchu/dusk-player-mac`, forked from `marvinvr/dusk-player`. It is a
Mac-first project for people who want focused access to their own Plex
libraries without promoted content or extra service layers.

The supported app target is `Dusk-macOS`, currently **macOS 26+ on Apple silicon
(arm64)**. `project.yml` is authoritative. An experimental `Dusk-tvOS` target adds an HD feasibility prototype, described
in [tvOS prototype](tvos-prototype.md); it is not a full supported TV client. The
fork has no iOS app target, mobile framework requirement, or Mac App Store release.

## Core Principles

- Plex owns metadata, libraries, watch state, and server identity.
- Store auth in Keychain; preferences in UserDefaults. Downloads, offline sync,
  and caches are explicit, documented exceptions to otherwise stateless use.
- Library order belongs to the Plex account, not a private Dusk sync service.
- Start playback direct. Remuxes may copy compatible video/audio into HLS;
  server video/audio re-encoding is prohibited for all Dusk playback. Refuse
  incompatible streams rather than silently converting them on the server.
- Keep view models observable and Plex-specific services straightforward.
- Use native Mac navigation, menus, keyboard/pointer controls, and AppKit bridges
  where SwiftUI needs a native rendering host. Follow `STYLE.md`.
- Favor a maintainable personal project over plugin systems and premature
  backend abstractions.

## Feature Scope

The Mac app provides Plex authentication and Home profiles, merged multi-server
Home/library/search data, detail screens, hybrid AVPlayer/VLCKit playback,
track selection, original-quality playback, timeline/watch-state reporting, intro/credits
skipping, continuous play, downloads/offline sync, Plex Live TV, and optional
Seerr requests. Availability depends on server capabilities and media.

AVPlayer retains HDR/Atmos remux and DuskDovi conversion paths. The stock desktop
VLC build does not advertise local TrueHD support; undecodable audio requires
another locally playable track rather than Plex conversion. HDR/audio output must be verified with actual media,
display, and audio hardware; compiling does not validate format fidelity.

The Mac UI has no PiP controls, AirPlay route picker, outgoing SharePlay invites,
system media-key integration, purchases, or alternate icon picker. App Intents
are inherited and compile, but Mac Siri/Shortcuts behavior is unverified.
Broader backends, DVR scheduling, and iOS support are outside current scope.

## Dependencies and Licensing

- Desktop VLCKit is checksum-pinned, fetched into git-ignored `Frameworks/`, and
  dynamically linked for LGPL compliance. No private upstream VLC repo access
  is needed for the Mac build.
- DuskDovi is an arm64 macOS static library built from `Native/DuskDovi` with a
  pinned Rust toolchain. New crates need corresponding license notices.
- XcodeGen owns project generation. System frameworks and URLSession are
  preferred elsewhere; artwork uses the existing Plex-aware image pipeline.

## Privacy and Network Boundaries

No advertising identifiers, Plex-derived telemetry, or third-party analytics
SDKs. The inherited release-build anonymous `app_opened` reporting uses the
upstream Rybbit endpoint described in `analytics.md`, with a random install ID,
no retry queue, and a Settings opt-out. Debug builds report nothing. This fork
does not own the upstream endpoint or its published privacy policy.

Network traffic is limited to Plex account/server APIs, media/artwork derived
from Plex, explicit optional Seerr setup/requests, that documented reporting,
explicit Group Activities sessions supported by the inherited coordination
code, and user-requested external links. Never log token-bearing URLs.

macOS Local Network permission is required for local Plex servers. A usage
description, sandbox entitlements, and correct signing are necessary build
pieces; the user still controls the permission in System Settings.
