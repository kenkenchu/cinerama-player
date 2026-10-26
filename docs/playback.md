# Mac Playback System

## Boundaries

`PlexService` owns metadata, playback URLs, decision/start endpoints, timeline and
watched-state calls. `StreamResolver` chooses the route/engine from media.
`PlaybackCoordinator` owns attempts, engine replacement, fallback, reporting and
Up Next. `PlayerViewModel` owns interaction, tracks and marker behavior.
`Playback/` contains the native AVPlayer/AppKit and desktop VLC implementations.

The Mac UI lives in `Features/Player/PlayerView.swift`. Feature views request
playback from the coordinator; they do not construct URLs or engines themselves.

## End-to-End Play Flow

1. A feature supplies a `PlexItemID`, optional resume offset/version, and a
   loading placeholder to the coordinator.
2. The coordinator resolves the item's server and fetches/checks Plex metadata,
   or uses matching downloaded metadata/media for local playback.
3. `StreamResolver` chooses AVPlayer or VLC and flags locally unplayable formats.
   Explicit versions remain bound to their requested server/file.
4. The coordinator constructs `PlaybackSource` and debug context, builds an
   engine, configures tracks, reporting and session identity, then
   commits under the player presentation ID.
5. `MacPlayerSession` creates its view model, wires coordinator callbacks and
   calls `startPlaybackIfNeeded`. The engine loads a source once per session.
   AVPlayer starts a ready item after any requested resume seek, before awaiting
   duration/media-selection discovery. HLS subtitle metadata must never gate
   starting video; discovery applies queued subtitle selection when available.
6. Finalization snapshots progress before stopping the engine and reporting
   stopped state. Cleanup cancels timers/attempts and closes server transcodes.

Every asynchronous attempt must check its captured identity before committing.
A dismissal, newer attempt or profile switch must supersede slow work. Late
answers must never replace a newer engine or cross the Plex Home boundary.

## Choosing the Server

Identifiers and rating keys collide across servers. All follow-up calls use
`activePlaybackServerID`. Cross-server fallback comes from the strong content-key
alternates index and changes the whole item/server binding together. Never pair
one server's metadata/stream IDs with another server's media URL.

Explicit watched actions can fan out through `PlexService+WatchedFanOut` to known
copies. Live timeline and transcode calls stay on the active playback server.

## Delivery Ladder and Session Hygiene

Direct play is the online startup baseline. Locally unplayable media, eligible
lossless remuxes and completed downloads take their documented routes. A failed
online direct attempt may retry through Plex HLS with `directStream=1`.
Server video/audio re-encoding is prohibited for every Cinerama playback route.
`transcodeLadderSession` rejects manual conversion and audio-conversion modes
before requesting a decision, and never constructs a start URL unless Plex
confirms both A/V streams are copied (`isLosslessRemux`). Missing decisions fail
closed. Subtitle text repackaging is allowed; burning subtitles is not.
The legacy universal "transcode" endpoint is still used for lossless HLS
packaging, with its existing session keepalives/cleanup; its name does not imply
encoding. The policy is client-scoped and does not change Plex server settings
or other clients. Quality presets are limited to Original and the menu is hidden.

Retain cancellation, stopped timelines, transcode keepalives/stop calls, selected
track carry-over and presentation identity when changing engines or delivery.
A video-copy decision is not proof that audio is copied: inspect both decisions
before accepting a lossless remux. `PlaybackDebugInfo` retains Plex stream
decisions from startup, remux, quality and server-fallback responses so the
overlay can distinguish video copying from audio/video transcoding. Metadata
refreshes preserve these session decisions; unavailable decisions stay explicit.

## Engines and Rendering

- Native video surfaces fill the player layout. The AVPlayer AppKit bridge
  reattaches its layer on view/window updates and only lets the current host
  resize or detach it, preventing outgoing SwiftUI hosts from changing the
  replacement surface. `PlaybackEngine.renderingDiagnostics` exposes safe
  renderer facts for the optional debug overlay, without URLs or credentials.
- `AVPlayerEngine`: standard-codec/container playback and HLS, native media
  selection, an `NSViewRepresentable` hosting `AVPlayerLayer`, remux resource
  loader, Dolby Vision proxy, and optional shared Metal enhancement renderer.
- `VLCKitEngine`: desktop `VLCMediaPlayer`/`VLCVideoView` in AppKit, Core Audio,
  per-source buffering, polled time/state/track lists, and sidecar subtitles.
  Opening/buffering states are reconciled with VLC's `isPlaying` flag; an
  actively playing transport must not remain in app-level startup/loading.
  Genuine buffering still uses the existing debounced loading presentation.
  The user confirmed the stuck spinner is resolved for the reported RM video;
  this is not a comprehensive VLC format/runtime audit.
- `PlaybackEngineFactory` may prewarm engines. The protocol keeps the view model
  independent of the selected engine.

Direct/local playback uses `StreamResolver.evaluateForDirectPlayback` with the
preferred audio and remembered/preferred subtitle IDs (nil subtitle means Off).
Container/video compatibility is still required, but unused audio/subtitle
tracks no longer force VLC. A selected sidecar requires VLC because AVPlayer
cannot mount it. The conservative whole-file `evaluate` remains available for
capability/remux checks; it does not represent the direct session's active tracks.

The player retains unsupported audio/embedded-subtitle choices from Plex metadata
when AVPlayer omits them. Synthetic menu IDs are never passed to AVPlayer.
Changing tracks re-evaluates direct/local sessions through the coordinator;
when the required engine changes, the same URL and delivery decision are kept,
with the engine position, pause state and explicit Plex track IDs carried over.
Changing back to compatible tracks can restore AVPlayer. TrueHD decoder errors,
HDR/Atmos remux, server HLS, AirPlay and Live TV keep their existing specialized
track/fallback paths. Existing engine overrides still take precedence.

The fork has no mobile raw-video bridge, mobile audio-session recovery pipeline,
TV renderer/HUD, display-mode matcher, or touch input bridge. Existing protocol
hooks for future PiP/external output do not imply a supported Mac UI.

### Dolby TrueHD decoding (TrueHD/MLP)

The fetched desktop framework is stock VideoLAN VLCKit 3.7.3. It lacks the Cinerama
TrueHD capability stamp; `VLCKitBuildInfo.decodesTrueHD` therefore defaults false.
Keep the existing metadata/track checks. An undecodable selection shows a visible
message requesting another audio track; server audio conversion is prohibited.
Never mark a track decodable just because it appears in VLC's track list.

The archived mobile audio postmortem does not describe this desktop Core Audio
implementation. Do not add mobile audio-session revive workarounds to it without
new desktop evidence.

### External (sidecar) subtitles

The player maps Plex stream metadata to engine tracks. Desktop VLC can mount
sidecars via playback slaves; AVPlayer cannot attach them to an already-playing
item, so an explicit selection may restart through VLC. Preserve stream IDs and
selected/off state across engine changes. Downloaded subtitle search/install remains Plex-owned.

## System Caption Appearance

macOS System Settings → Accessibility → Captions is the sole source of subtitle
appearance. Cinerama has no subtitle size/style picker or stored appearance override;
the obsolete `subtitleFontSize` preference is removed at preferences startup.
AVPlayer leaves `textStyleRules` unset so native caption rendering uses the
system settings and their content-override behavior.

VLC does not consume macOS caption preferences itself. `SystemCaptionStyle`
reads MediaAccessibility's user-domain font family, relative size, text/background
colors and opacity, and text edge style, then translates these to VLC FreeType
options. The player uses a private VLC instance so font options are applied at
renderer initialization, and refreshes it on the next load if the system style
changed. Raised/depressed edges use VLC's shadow approximation; caption-window
geometry and advanced authored ASS styling do not have a complete native match.
This adapter exposes no independent Cinerama or VLC styling preferences.

Bitmap subtitles and text already burned into video cannot adopt system styles.
Verify caption appearance with real text tracks on both engines; a successful
build does not establish visual parity.

The user subsequently confirmed that the missing-subtitle behavior reported
following the system-style change works now. This is no longer an open issue.
No specific root cause was isolated; broader subtitle-format and engine coverage
still requires runtime verification.


## Dolby Atmos and Spatial Audio

`PlaybackCoordinator+SpatialAudio` and Plex playback endpoints determine remux
eligibility. A remux copies media into HLS for AVPlayer and may restore missing
Atmos signaling through `RemuxHLSLoader`. Accept the lossless path only when
Plex confirms that both relevant video/audio streams are copied. Actual Mac
spatial/HDR output depends on the hardware, route, format and server.

## HDR Video and Dolby Vision 8 (HDR Remux)

Preserve format metadata, video-copy checks, HDR signaling and the remux loader
when handling HDR10/HDR10+/HLG and compatible Dolby Vision profiles. Do not
assume an HLS container alone makes a locally unsupported video profile safe.

## Dolby Vision Profile 5

Profile 5 has no HDR10-compatible base layer. The resolver's local playability
and remux/server route checks must remain authoritative; unsupported direct
rendering can produce incorrect colors instead of an obvious playback error.

## Dolby Vision 7 (on-device 8.1 conversion)

`Playback/DolbyVision7/` owns the loopback HLS proxy and fMP4/playlist rewriting.
`DoviBridge` is the only Swift face of the pinned Rust converter. It converts
profile 7 RPU signaling to compatible 8.1 output where eligible. If conversion
fails, retry the remux unconverted for its HDR10 base layer; do not silently
claim successful Dolby Vision conversion. Retain the proxy for the engine's
lifetime and stop it at teardown. The Mac sandbox needs server/client network
entitlements for the loopback path as well as Plex traffic.

## Video Enhancement

The shared Metal renderer can enhance AVPlayer video on an AppKit layer host,
paced by a screen display link. Auto is the default for an unset preference;
existing explicit preferences are preserved. Auto applies Lanczos scaling and
adaptive sharpening to SDR video at up to 50 fps only when the fitted picture
needs at least 8% upscaling. The decision uses display backing pixels, accounts
for letterboxing/aspect-fill, and updates during resize, fullscreen and display
changes. Otherwise AVPlayer's native layer remains visible and Metal frame
submission is skipped. Native rendering also handles HDR and selected AVPlayer
subtitles; existing remux/HLS route exclusions remain in effect.
Desktop VLC uses its native renderer
and does not run that Metal path. A control/setting in shared state is not a
claim that desktop VLC implements the feature.

The diagnostics overlay reports the active rendering path and enhancement
reason. This policy has compile-only verification; actual image quality, colour
accuracy and performance on the M2 still require real-media comparison.

## Live TV Play Flow and Timeline

The highest-priority enabled server supplies the lineup. Tuning produces a Plex
virtual session and HLS source, not an ordinary library file. Preserve its
session ID for keepalives. Seek against the sliding seekable window and use
`PlayerLiveTimeline`'s wall-clock/live-edge model. Live sessions report stopped
state but never scrobble a program as library content.

The current UI loads only provider/channel metadata, then builds a lineup with
empty program lists. No grid/watch-now EPG requests gate Home, the Live TV tab or
tuning. Channel-only sessions do not start the schedule-refresh task; their
titles use channel names and LIVE status. The inherited timeline/guide helpers
remain available internally, but are not required by the channel browser.

The tune result retains Plex's HLS stream decisions for diagnostics and engine
selection. Delivered codecs take priority over tuner-input metadata; missing
codecs alone do not disqualify AVPlayer. Known incompatible codecs still route
to VLC. An AVPlayer Live HLS error, or 12 seconds without advancing playback
during startup (excluding pause), gets one VLC retry using the same URL and
tuner/transcode session at the live edge (unless AVPlayer/AirPlay was forced),
without tuning a second channel session. The existing failure watch owns this
retry and is cancelled on dismissal or engine replacement.

Live HLS advertises original MPEG-2/H.264/HEVC and common tuner audio as copy
targets rather than imposing an H.264/AAC conversion target. HEVC in MPEG-TS
uses VLC. If Plex cannot confirm a copy-only session, tuning reports the policy
error rather than starting a converted stream.

Live diagnostics label the seekable buffer separately from playback position;
it is not the program's total duration. They show Plex's reported output codecs,
container and copy/transcode decisions, explicitly retaining unavailable values
when Plex omits them. Hardware decoding is not inferred from these decisions.

The native seek slider binds to normalized `timelineProgress`/`timelinePosition`
from the live clock snapshot, not directly to the segment-stepped HLS seekable
bounds. Watching live keeps the thumb at the live edge instead of jumping back
on playlist updates; actual seeks still clamp to the reachable buffer.

The user confirmed a real Live TV channel plays through VLC as copied MPEG-2
video and AC3 6-channel audio after the copy-only policy change. That confirms
this channel's delivery, not all tuner formats or hardware decoding. The user
also confirmed the channel-grid layout and live-slider fix both work. These
changes passed signed builds; broader tuner, seek and format coverage remains
unverified.

## Experimental Metal MPEG-2 Reconstruction

The Mac Settings page has **Live TV decoding experiment → MPEG-2 decoder** with
Standard playback (default), Experimental CPU and Experimental Metal. Retuning a
known MPEG-2 channel selects the experiment; forced player overrides and AirPlay
win. Other media stays on the existing resolver. The existing copy-only Plex
session and keepalives remain coordinator-owned.

`Native/CineramaMPEG2` builds a checksum-pinned LGPL FFmpeg decoder into a Mac-only
framework. Both experimental modes decode real MPEG-2/HLS locally. CPU mode uses
FFmpeg's IDCT; Metal mode replaces luma/chroma IDCT and residual reconstruction
with GPU work. Parsing and frame/field motion compensation remain CPU work.
Native audio/video sample renderers share one clock, bounded decode-ahead and
cancellable input. Cmd-I exposes the actual path and GPU block count.

Experimental audio supports track selection and preserves supported source PCM
channel layouts/sample rates; default device output and physical surround need
user verification. Live TV captions and DVR are explicitly out of scope. BWDIF supplies progressive output at field cadence for
interlaced video; progressive input retains its cadence. Startup waits for
audio/video buffer coverage, and Cmd-I exposes queue starvation observations. Unsupported controls are
disabled. Retryable input/output interruptions reconnect to the same session URL and
mode with a three-attempt budget. Timestamp jumps reanchor the output clock;
long-pause resume refreshes the live session. Permanent errors remain explicit,
with Standard playback available on retune. No automatic CPU fallback masks an
A/B result. See the
[native experiment README](../Native/CineramaMPEG2/README.md) for architecture,
run commands, real-stream tests and performance results. The Metal path is
currently slower than CPU on generated HD fixtures; CPU/energy savings have not
been established. User ran both modes with real Live TV; picture/audio parity remains unverified.
See the [resumable pipeline plan](live-tv-pipeline-plan.md) for milestone progress.

The earlier [standalone block prototype](../Native/MetalMPEG2Prototype/README.md)
remains an independent mathematical kernel test; its synthetic throughput is not
an end-to-end decoder benchmark.

## Timeline, Scrobble, and Up Next

Online sessions report on the active server and maintain transcode keepalives.
Local downloads queue progress through `OfflinePlaybackSyncManager`. Loading
reports must not regress progress to zero. Library scrobble happens once after
90 percent of runtime; live sessions never scrobble.

`PlayerViewModel` syncs the engine, maintains track/marker state, and forwards
snapshots. Credits can raise a small Up Next action or the end-of-session
presentation. Countdown state respects pauses, per-session spent markers,
continuous play and passout protection. Replacing an engine must not reset those
guards or let old snapshots update the new session.

Finalize before loading the next episode. Failed transitions keep an actionable
error instead of leaving a stopped engine hidden behind a loading screen.
The Mac player prevents display sleep with a ProcessInfo activity while mounted.

## Settings and Preferences

`UserPreferences` persists language, skip/continuous-play,
remux/enhancement and download preferences. `SettingsMacView` exposes the current
Mac controls. Manual subtitle selections persist a local preference scoped to the
Plex profile, server, and movie rating key or TV series rating key. This remembers
Off or the language, forced/hearing-impaired flags, and title; file-specific
stream IDs are never persisted as preferences. Reopening a movie or starting a
later episode prefers a matching track (exact title first), including after app
restarts. If none matches, selection falls back to the normal language settings.
Live TV does not update this preference. Movie and series preferences use separate
storage keys; existing series choices survive updates. Explicit session carry-over
still wins during engine changes, and startup server/remux decisions use the same
saved choice.
A remembered sidecar can select the existing VLC route just as an explicit
selection does. Automatic selection does not overwrite the stored preference.
Quality changes are session-only. Shared stored fields or protocol
hooks may have no Mac UI; check the concrete consumer before promising a feature.

## Where to Edit and Verify

- Format/engine decisions: `StreamResolver`.
- Native rendering/engine behavior: `AVPlayerEngine`, `VLCKitEngine`, Metal renderer.
- Attempts/fallback/track handoff: coordinator session/spatial-audio extensions.
- Track mapping/automatic choices: player view model track-selection extension.
- Transport/markers: player view model controls and native `PlayerView`.
- URLs/server decisions: `PlexService+Playback`.
- Proxy/conversion: `Playback/DolbyVision7` and `Native/CineramaDovi`.

Run the signed `scripts/build_macos.sh` and applicable automated tests after code
changes, following [testing](testing.md). Automated test hosts are authorized;
manual app launches and visual inspection remain user-owned. Runtime validation
must use real Plex media; compilation does not prove codec support, audio output,
HDR fidelity or playback recovery. Detailed
pre-fork algorithms and removed-platform history are archived in
`upstream/playback.md`; active Mac source remains authoritative.
