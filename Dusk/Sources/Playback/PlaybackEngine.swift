import AppKit
import AVFoundation
import CoreText
import MediaAccessibility
import SwiftUI

/// Which concrete engine to use for playback.
enum PlaybackEngineType: Sendable {
    case avPlayer
    case vlcKit
}

/// Where a playback source's bytes actually come from, resolved by the
/// coordinator when the source is built. Drives how much protective buffering
/// the engine needs: a downloaded file has no jitter at all, a LAN Plex
/// server very little, and only a remote/relay stream needs real headroom.
enum PlaybackSourceLocality: Sendable {
    case localFile
    case localNetwork
    case remoteNetwork
}

enum PlaybackBufferPolicy {
    static let avPlayerForwardBufferDuration: TimeInterval = 20

    static func vlcCachingMilliseconds(for locality: PlaybackSourceLocality) -> Int {
        switch locality {
        case .localFile: 300
        case .localNetwork: 600
        case .remoteNetwork: 1_500
        }
    }
}

struct PlaybackEngineDiagnostic: Sendable, Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

/// Receives Picture in Picture lifecycle events from a `PlaybackEngine` so the
/// owner (the coordinator) can keep the session alive while the floating window
/// is shown and restore the player UI when the user returns from it.
@MainActor
protocol PlaybackPictureInPictureDelegate: AnyObject {
    /// The floating window started (`true`) or stopped (`false`).
    func pictureInPictureActiveDidChange(_ isActive: Bool)

    /// The user asked to return to the full app UI from the PiP window. Call
    /// `completion(true)` once the player UI is back on screen so the system can
    /// animate the video back into place.
    func pictureInPictureRestorePlayerUI(completion: @escaping (Bool) -> Void)
}

/// Unified interface for media playback. Concrete implementations wrap
/// AVPlayer (`AVPlayerEngine`) or VLCKit (`VLCKitEngine`).
///
/// Implementations must be `@Observable` so SwiftUI views can react
/// to state changes (currentTime, playback state, track lists, etc.).
@MainActor
protocol PlaybackEngine: AnyObject {
    // MARK: - Lifecycle

    /// Begin loading media from the given URL. If `startPosition` is non-nil,
    /// seek to that offset once loaded (resume playback).
    func load(source: PlaybackSource)
    func configureVideoEnhancement(_ request: VideoEnhancementRequest)
    func play()
    func pause()
    func stop()
    func seek(to position: TimeInterval)
    func setPlaybackRate(_ rate: Float)

    // MARK: - Coordinated playback

    /// Apple's transport coordinator for this engine. AVPlayer supplies one
    /// natively; VLCKit is adapted through AVDelegatingPlaybackCoordinator.
    var playbackCoordinator: AVPlaybackCoordinator { get }

    /// Sets the stable server-scoped identity used to match this item with the
    /// copies loaded by other SharePlay participants. Nil detaches local custom
    /// playback behavior after leaving the group.
    func configureCoordinatedPlayback(itemIdentifier: String?)

    /// Seek with a precision hint. `precise: false` lets the engine trade
    /// frame accuracy for speed (e.g. AVPlayer snapping to a nearby keyframe
    /// instead of decoding up to the exact frame) — meant for transient jumps
    /// like double-tap/remote skips where the position is approximate anyway.
    /// `precise: true` behaves like `seek(to:)`. Engines that don't
    /// distinguish keep the default, which forwards to `seek(to:)`.
    func seek(to position: TimeInterval, precise: Bool)
    func recoverFromStall()

    /// Called when the app returns to foreground after being backgrounded.
    /// Engines should restore their video rendering pipeline here.
    func handleReturnToForeground()

    func setVideoFillEnabled(_ enabled: Bool)

    // MARK: - State

    var state: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    /// The currently seekable media-time window. Live HLS commonly starts
    /// above zero and advances at its upper edge as Plex appends segments.
    var seekableTimeRange: ClosedRange<TimeInterval>? { get }
    var isBuffering: Bool { get }
    var error: PlaybackError? { get }
    var videoEnhancementStatus: VideoEnhancementStatus { get }
    var onPlaybackEnded: (@MainActor () -> Void)? { get set }
    var playbackDiagnostics: [PlaybackEngineDiagnostic] { get }

    // MARK: - Track Selection

    var availableSubtitleTracks: [SubtitleTrack] { get }
    var availableAudioTracks: [AudioTrack] { get }
    var selectedSubtitleTrackID: Int? { get }
    var selectedAudioTrackID: Int? { get }
    func selectSubtitleTrack(_ track: SubtitleTrack?)
    func selectAudioTrack(_ track: AudioTrack)

    /// Whether the engine can mount an external (sidecar) subtitle file on the
    /// media it is already playing. VLCKit adds one as a libvlc playback slave;
    /// AVPlayer cannot attach a sidecar to a live item at all (it would need an
    /// AVComposition rebuild), so a Plex sidecar there requires restarting the
    /// session on VLCKit.
    var supportsExternalSubtitles: Bool { get }

    /// Mounts a sidecar subtitle file (a Plex `/library/streams/{id}` URL) on
    /// the current media, optionally making it the active subtitle track.
    ///
    /// The track appears in `availableSubtitleTracks` asynchronously, carrying
    /// `externalURL == url` so the caller can map it back to the Plex stream it
    /// came from. Returns whether the engine accepted the request, not whether
    /// the file parsed. Engines must remember their mounted slaves and re-add
    /// them whenever they reopen the media in place (slaves live on the input,
    /// not on the media).
    @discardableResult
    func attachExternalSubtitle(_ url: URL, select: Bool) -> Bool

    /// Whether automatic (app-driven) audio track selection may run right now.
    /// VLCKit defers it until playback is steadily rendering: switching the
    /// audio ES restarts libvlc's audio output (input format change), and doing
    /// that inside the startup window — output bring-up, audio session
    /// activation, resume seek — can leave the restarted output dead until a
    /// manual pause/resume. Steady-state switches are safe.
    var isReadyForAutomaticAudioSelection: Bool { get }

    /// An audio track whose decoder turned out not to work during this load
    /// (VLCKit: libvlc reported that it could not open the TrueHD decoder).
    /// The view model hands it to the server audio-conversion fallback once.
    var failedAudioDecoderTrackID: Int? { get }

    // MARK: - Audio session

    var prefersSpatializedAudioSession: Bool { get }

    // MARK: - External playback

    /// Whether the engine can hand video to a system external-playback route.
    /// AVPlayer supports native AirPlay; VLCKit's renderer remains local.
    var supportsExternalPlayback: Bool { get }

    /// Whether the engine is currently rendering video on an external route.
    var isExternalPlaybackActive: Bool { get }

    // MARK: - Rendering

    /// Returns a platform-specific view that renders the video content.
    func makePlayerView() -> AnyView

    /// Bumped when the engine replaces its rendering view mid-session (VLCKit
    /// entering Picture in Picture support mode); `PlayerViewModel` re-calls
    /// `makePlayerView()` when it changes. Engines with a stable view keep the
    /// default 0.
    var playerViewGeneration: Int { get }

    // MARK: - Picture in Picture

    var isPictureInPicturePossible: Bool { get }

    /// Whether a Picture in Picture window is currently active.
    var isPictureInPictureActive: Bool { get }

    /// Routes PiP lifecycle events back to the owner. Held weakly.
    func setPictureInPictureDelegate(_ delegate: (any PlaybackPictureInPictureDelegate)?)

    func startPictureInPicture()
    func stopPictureInPicture()

}

extension PlaybackEngine {
    var seekableTimeRange: ClosedRange<TimeInterval>? {
        duration > 0 ? 0...duration : nil
    }

    var playbackDiagnostics: [PlaybackEngineDiagnostic] { [] }
    func setVideoFillEnabled(_ enabled: Bool) {}

    // Bumped when the engine replaces its rendering view mid-session (VLCKit
    // entering Picture in Picture support mode); `PlayerViewModel` re-calls
    // `makePlayerView()` when it changes. Engines with a stable view keep 0.
    var playerViewGeneration: Int { 0 }

    // Default: the precision hint is ignored — only AVPlayer distinguishes
    // tolerant (keyframe) seeks from frame-accurate ones.
    func seek(to position: TimeInterval, precise: Bool) {
        seek(to: position)
    }

    // Default: no startup fragility — only VLCKit defers automatic selection.
    var isReadyForAutomaticAudioSelection: Bool { true }

    // Default: decoders are the platform's own. Only VLCKit watches its
    // TrueHD decoder.
    var failedAudioDecoderTrackID: Int? { nil }

    // Default: sidecar subtitles cannot be mounted. Only VLCKit opts in.
    var supportsExternalSubtitles: Bool { false }
    @discardableResult
    func attachExternalSubtitle(_ url: URL, select: Bool) -> Bool { false }

    // Default: keep the rich movie-playback session. Only VLCKit opts out.
    var prefersSpatializedAudioSession: Bool { true }

    // Native external video playback is AVPlayer-only. Engines opt in.
    var supportsExternalPlayback: Bool { false }
    var isExternalPlaybackActive: Bool { false }

    var isPictureInPicturePossible: Bool { false }
    var isPictureInPictureActive: Bool { false }
    func setPictureInPictureDelegate(_ delegate: (any PlaybackPictureInPictureDelegate)?) {}
    func startPictureInPicture() {}
    func stopPictureInPicture() {}
}

/// Adapts the system caption preferences for VLC, which does not read them itself.
/// There is no Dusk-owned style or persisted renderer preference.
@MainActor
enum SystemCaptionStyle {
    static var vlcOptions: [String] {
        let domain = MACaptionAppearanceDomain.user
        let foreground = MACaptionAppearanceCopyForegroundColor(domain, nil).takeRetainedValue()
        let background = MACaptionAppearanceCopyBackgroundColor(domain, nil).takeRetainedValue()
        let descriptor = MACaptionAppearanceCopyFontDescriptorForStyle(domain, nil, .default).takeRetainedValue()
        let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
        let scale = MACaptionAppearanceGetRelativeCharacterSize(domain, nil)
        let edge = MACaptionAppearanceGetTextEdgeStyle(domain, nil)
        let hasOutline = edge == .uniform
        let hasShadow = edge == .dropShadow || edge == .raised || edge == .depressed
        var options = [
            "--freetype-rel-fontsize=\(max(1, Int((16 / max(scale, 0.1)).rounded())))",
            "--freetype-color=\(rgb(foreground))",
            "--freetype-opacity=\(opacity(MACaptionAppearanceGetForegroundOpacity(domain, nil)))",
            "--freetype-background-color=\(rgb(background))",
            "--freetype-background-opacity=\(opacity(MACaptionAppearanceGetBackgroundOpacity(domain, nil)))",
            "--freetype-outline-thickness=\(hasOutline ? 4 : 0)",
            "--freetype-shadow-opacity=\(hasShadow ? 128 : 0)"
        ]
        if let family { options.append("--freetype-font=\(family)") }
        return options
    }

    private static func opacity(_ value: CGFloat) -> Int {
        Int((min(1, max(0, value)) * 255).rounded())
    }

    private static func rgb(_ color: CGColor) -> Int {
        guard let color = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return 0 }
        return (opacity(color.redComponent) << 16) | (opacity(color.greenComponent) << 8) | opacity(color.blueComponent)
    }
}
