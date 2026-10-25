import Foundation
import AVFoundation
import AVKit
import Testing
@testable import CineramaTV

@Suite("TV copy-only playback and lifecycle")
@MainActor
struct TVPlaybackTests {
    @Test func onlyConfirmedAudioAndVideoCopiesCanStartHLS() throws {
        let good = decisions()
        try TVPlaybackCoordinator.validateRemux(outcome: .transcodeAvailable, streams: good, hasSubtitle: false)
        for value: String? in [nil, "transcode", "directplay"] {
            var badVideo = good
            badVideo.videoDecision = value
            #expect(throws: TVPlaybackFailure.self) {
                try TVPlaybackCoordinator.validateRemux(outcome: .transcodeAvailable, streams: badVideo, hasSubtitle: false)
            }
            var badAudio = good
            badAudio.audioDecision = value
            #expect(throws: TVPlaybackFailure.self) {
                try TVPlaybackCoordinator.validateRemux(outcome: .transcodeAvailable, streams: badAudio, hasSubtitle: false)
            }
        }
        for outcome: PlexService.TranscodeDecisionOutcome in [.directPlayOnly, .failed(nil)] {
            #expect(throws: TVPlaybackFailure.self) {
                try TVPlaybackCoordinator.validateRemux(outcome: outcome, streams: good, hasSubtitle: false)
            }
        }
    }

    @Test func subtitleBurningIgnoringOrMissingSegmentsAreRejected() throws {
        var streams = decisions()
        streams.subtitleDecision = "copy"
        streams.subtitleLocation = "segments-subs"
        try TVPlaybackCoordinator.validateRemux(outcome: .transcodeAvailable, streams: streams, hasSubtitle: true)
        for decision: String? in ["burn", "ignore"] {
            streams.subtitleDecision = decision
            #expect(throws: TVPlaybackFailure.self) {
                try TVPlaybackCoordinator.validateRemux(outcome: .transcodeAvailable, streams: streams, hasSubtitle: true)
            }
        }
        streams.subtitleDecision = "copy"
        streams.subtitleLocation = nil
        #expect(throws: TVPlaybackFailure.self) {
            try TVPlaybackCoordinator.validateRemux(outcome: .transcodeAvailable, streams: streams, hasSubtitle: true)
        }
    }

    @Test func finalizationIsIdempotentAndCannotRestartARetiredSession() async throws {
        let media = try TVTestFixtures.media()
        let playback = TVPlaybackCoordinator(service: PlexService(), details: try TVTestFixtures.details(),
            choice: try TVStreamResolver.choice(media: media, index: 0), resume: false)
        // Exercise player cleanup without network access or playing an asset.
        playback.player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: "/nonexistent-test-video.mp4")))
        playback.setForeground(false)
        #expect(playback.player.rate == 0)
        await playback.finish()
        await playback.finish()
        #expect(playback.stopped)
        #expect(playback.player.currentItem == nil)
        #expect(playback.progressMessage == nil)
        playback.start()
        #expect(!playback.started)
        #expect(!playback.loading)
    }

    @Test func nativeBackDelegatesDismissalWithoutLosingThePlayer() {
        let player = AVPlayer()
        var dismissals = 0
        let view = TVNativePlayer(player: player, close: { dismissals += 1 })
        let delegate = view.makeCoordinator()
        let controller = AVPlayerViewController()
        controller.player = player
        #expect(!delegate.playerViewControllerShouldDismiss(controller))
        #expect(dismissals == 1)
        #expect(controller.player === player)
    }

    private func decisions() -> PlexService.TranscodeStreamDecisions {
        .init(container: "mp4", videoDecision: "copy", videoCodec: "h264",
              audioDecision: "copy", audioCodec: "aac", subtitleDecision: nil, subtitleLocation: nil)
    }
}
