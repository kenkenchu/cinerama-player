# Product and Scope

## Product Shape

Cinerama is a native macOS/tvOS Plex client maintained in
`kenkenchu/cinerama-player` and developed independently without upstream
synchronization. Original-project credit is in README.md; license notices are
preserved. It is a
two-platform project for people who want focused access to their own Plex
libraries without promoted content or extra service layers.

Maintained targets are **Cinerama-macOS: macOS 26+ on Apple silicon** and
**Cinerama-tvOS: tvOS 26+ on Apple TV HD (A8)**, with the user's TV running 26.6.
`project.yml` is authoritative. tvOS 26 remains the required compatibility baseline
for Apple TV HD; newer SDKs/runtimes must not raise the minimum requirement.
Automated TV tests default to a local tvOS 26.x simulator. The TV client is growing from user-confirmed
library playback and text-subtitle feasibility; it does not yet match Mac
features. See [TV design](tvos-design.md) and [TV UI](tvos-ui.md).
No iOS app target or App Store release is maintained.

## Core Principles

- Plex owns metadata, libraries, watch state, and server identity.
- Store auth in Keychain; preferences in UserDefaults. Downloads, offline sync,
  and caches are explicit, documented exceptions to otherwise stateless use.
- Library order belongs to the Plex account, not a private Cinerama sync service.
- Start playback direct. Remuxes may copy compatible video/audio into HLS;
  server video/audio re-encoding is prohibited for all Cinerama playback. Refuse
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

AVPlayer retains HDR/Atmos remux and CineramaDovi conversion paths. The stock desktop
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
and versions explain the limitation. Experimental HD MPEG-2 Live TV now has
opt-in CPU/Metal decoding; see
[TV Live TV](tvos-live-tv.md). TV VLC, automatic next episode,
downloads and HDR conversion are deferred; prioritize library playback first.

## Dependencies and Licensing

- Desktop VLCKit is checksum-pinned, fetched into git-ignored `Frameworks/`, and
  dynamically linked for LGPL compliance. No private upstream VLC repo access
  is needed for the Mac build.
- The opt-in Mac/TV MPEG-2 Live TV experiment builds a pinned LGPL FFmpeg into
  `CineramaMPEG2.framework`. Standard playback still uses AVPlayer/VLC; the
  experiment has explicit caption/audio/seek limits. See
  [playback](playback.md#experimental-metal-mpeg-2-reconstruction).
- CineramaDovi is an arm64 macOS static library built from `Native/CineramaDovi` with a
  pinned Rust toolchain. New crates need corresponding license notices.
- XcodeGen owns project generation. System frameworks and URLSession are
  preferred elsewhere; artwork uses the existing Plex-aware image pipeline.

## Privacy and Network Boundaries

No advertising identifiers, Plex-derived telemetry, or third-party analytics
SDKs. Cinerama has no analytics endpoint configured and sends no usage events in
Debug or Release. See [analytics](analytics.md) and [privacy](privacy.md).

Network traffic is limited to Plex account/server APIs, media/artwork derived
from Plex, explicit optional Seerr setup/requests, explicit Group Activities
sessions supported by inherited coordination code, and user-requested external
links. Never log token-bearing URLs.

macOS Local Network permission is required for local Plex servers. A usage
description, sandbox entitlements, and correct signing are necessary build
pieces; the user still controls the permission in System Settings.

## Cinerama Application Identity

The project, schemes, source folders, Swift modules, icons and native converter
all use Cinerama naming. Both platforms build as `Cinerama.app` in their own
product directories. Schemes are `Cinerama-macOS` and `Cinerama-tvOS` in
`Cinerama.xcodeproj`; the converter is `Native/CineramaDovi`.

The user explicitly chose new identifiers: `com.cinerama-player.mac` and
`com.cinerama-player.tv`. Keychain uses `com.cinerama-player.app`; local downloads
use `Application Support/Cinerama/Downloads`. Background-session and group
activity identifiers also use the new namespace. This creates a separate app,
preferences, Keychain and storage identity. First launch requires Plex sign-in
and local preferences to be set again. Existing apps and their stored data are
not deleted or automatically migrated. TV requires its new development profile
and a separate install before runtime verification.

Original-project naming survives only in README's credit section and Git
history. Copyright and third-party license notices remain preserved.
