import Foundation


@MainActor
final class PlaybackNowPlayingController {

    func beginSession(
        details: PlexMediaDetails,
        engine: any PlaybackEngine,
        plexService: PlexService,
        skipBackwardInterval: TimeInterval,
        skipForwardInterval: TimeInterval
    ) {
    }

    func beginLiveSession(
        title: String,
        channelTitle: String,
        artworkPath: String?,
        serverID: String?,
        engine: any PlaybackEngine,
        plexService: PlexService,
        skipBackwardInterval: TimeInterval,
        skipForwardInterval: TimeInterval
    ) {
    }

    /// Follows the tuned channel's schedule: a live session outlives the
    /// program it started on, and the lock screen should not still be naming
    /// the show that ended an hour ago. Title only — the channel artwork stays
    /// put across program changes.
    func updateLiveProgramTitle(_ title: String) {
    }

    func updatePlaybackState(
        state: PlaybackState,
        currentTime: TimeInterval,
        duration: TimeInterval,
        force: Bool = false
    ) {
    }

    func endSession(deactivateAudioSession: Bool = true) {
    }
}
