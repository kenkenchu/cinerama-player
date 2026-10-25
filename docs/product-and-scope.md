# Product and Scope

## Product Shape

Cinerama (formerly Dusk Player) is a native macOS/tvOS Plex client maintained in
`kenkenchu/dusk-player-mac`. It originated from `marvinvr/dusk-player` and is now
developed independently without routine upstream synchronization. Original
credits and license notices are preserved. It is a
two-platform project for people who want focused access to their own Plex
libraries without promoted content or extra service layers.

Maintained targets are **Dusk-macOS: macOS 26+ on Apple silicon** and
**Dusk-tvOS: tvOS 26+ on Apple TV HD (A8)**, with the user's TV running 26.6.
`project.yml` is authoritative. The TV client is growing from user-confirmed
library playback and text-subtitle feasibility; it does not yet match Mac
features. See [TV design](tvos-design.md) and [TV UI](tvos-ui.md).
No iOS app target or App Store release is maintained.

## Core Principles

- Plex owns metadata, libraries, watch state, and server identity.
- Store auth in Keychain; preferences in UserDefaults. Downloads, offline sync,
  and caches are explicit, documented exceptions to otherwise stateless use.
- Library order belongs to the Plex account, not a private Dusk sync service.
- Start playback direct. Remuxes may copy compatible video/audio into HLS;
  server video/audio re-encoding is prohibited for all Dusk playback. Refuse
  incompatible streams rather than silently converting them on the server.
- Keep view models observable and Plex-specific services straightforward.
- Use distinct native Mac and TV interfaces. Mac follows `STYLE.md`; TV uses
  remote/focus navigation and AVKit controls, following `tvos-ui.md`.
- Apple TV HD rejects 4K/UHD with an informational message. Do not add local
  downscaling or server conversion. Mac capabilities remain independent.
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

The TV library client provides Plex linking/Home profiles, merged Home shelves
and a cinematic Continue Watching hero, personalized genre shelves,
watched/removal actions, account-ordered libraries, artwork grids, cross-server
search, media details, compatible audio/text-subtitle choices, resume and
server-scoped watch-state reporting. Choices are remembered per profile/server/
movie or series. Caption appearance derives from tvOS accessibility settings;
its explicit-override adapter still needs user visual verification. Native
AVPlayer and copy-only HLS handle compatible HD SDR sources. Unsupported tracks
and versions explain the limitation. Live TV, TV VLC, automatic next episode,
downloads and HDR conversion are deferred; prioritize library playback first.

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
SDKs. The Mac app’s inherited release-build anonymous `app_opened` reporting uses the
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

## App Naming and Upgrade Identity

Both apps display Cinerama and build as `Cinerama.app` in their separate Mac/TV
product directories. The Xcode project, schemes, source folders and Swift module
names retain Dusk naming. Bundle identifiers, Keychain keys, UserDefaults keys,
Plex client identifiers and download/cache paths remain unchanged so the rename
does not create a separate account or storage domain. Plex product labels and
sign-in prompts use Cinerama. Existing Dusk app copies are not removed by builds.
