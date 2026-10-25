import Foundation

/// Creates the correct `PlaybackEngine` for a given media item.
///
/// Usage:
/// ```swift
/// let details: PlexMediaDetails = ...
/// let media = details.media[0]
/// let engine = PlaybackEngineFactory.makeEngine(for: media)
/// ```
@MainActor
enum PlaybackEngineFactory {
    private static var warmedAVPlayerEngine: AVPlayerEngine?

    private static var warmedVLCKitEngine: VLCKitEngine?

    /// Front-load one-time player setup so first playback does not pay the
    /// initialization cost while the user is waiting for video to start.
    static func prewarmIfNeeded() {
        if warmedAVPlayerEngine == nil {
            warmedAVPlayerEngine = AVPlayerEngine()
        }

        if warmedVLCKitEngine == nil {
            warmedVLCKitEngine = VLCKitEngine()
        }
    }

    /// Build a playback engine for the given media.
    ///
    /// - Parameters:
    ///   - media: The Plex media version to play.
    ///   - forceAVPlayer: User preference override to always use AVPlayer.
    ///   - forceVLCKit: User preference override to always use VLCKit.
    /// - Returns: A configured `PlaybackEngine` ready for `load(url:startPosition:)`.
    static func makeEngine(
        for media: PlexMedia,
        forceAVPlayer: Bool = false,
        forceVLCKit: Bool = false
    ) -> any PlaybackEngine {
        let engineType = StreamResolver.resolve(
            media: media,
            forceAVPlayer: forceAVPlayer,
            forceVLCKit: forceVLCKit
        )

        switch engineType {
        case .avPlayer, .vlcKit:
            return makeEngine(type: engineType)
        }
    }

    static func makeEngine(type engineType: PlaybackEngineType) -> any PlaybackEngine {
        switch engineType {
        case .avPlayer:
            if let warmedAVPlayerEngine {
                self.warmedAVPlayerEngine = nil
                return warmedAVPlayerEngine
            }
            return AVPlayerEngine()
        case .vlcKit:
            if let warmedVLCKitEngine {
                self.warmedVLCKitEngine = nil
                return warmedVLCKitEngine
            }
            return VLCKitEngine()
        }
    }
}
