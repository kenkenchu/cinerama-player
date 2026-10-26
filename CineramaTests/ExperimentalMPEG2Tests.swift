import AVFoundation
import Testing
@testable import Cinerama

@Suite("Experimental MPEG-2 routing and lifecycle")
@MainActor struct ExperimentalMPEG2Tests {
    @Test func onlyMPEG2WithoutPlayerOverridesIsEligible() {
        for codec in ["mpeg2video", "mpeg2", "mp2v", "MPEG2VIDEO"] {
            #expect(ExperimentalMPEG2Mode.applies(codec: codec, forceAVPlayer: false, forceVLC: false, airPlay: false))
        }
        for codec: String? in [nil, "h264", "hevc", "av1", "mpeg1video"] {
            #expect(!ExperimentalMPEG2Mode.applies(codec: codec, forceAVPlayer: false, forceVLC: false, airPlay: false))
        }
        #expect(!ExperimentalMPEG2Mode.applies(codec: "mpeg2video", forceAVPlayer: true, forceVLC: false, airPlay: false))
        #expect(!ExperimentalMPEG2Mode.applies(codec: "mpeg2video", forceAVPlayer: false, forceVLC: true, airPlay: false))
        #expect(!ExperimentalMPEG2Mode.applies(codec: "mpeg2video", forceAVPlayer: false, forceVLC: false, airPlay: true))
    }
    @Test func experimentalCapabilitiesAreExplicitAndStopIsIdempotent() {
        for mode in [ExperimentalMPEG2Mode.cpu, .metal] {
            let engine = ExperimentalMPEG2Engine(mode: mode)
            #expect(!engine.supportsSeeking)
            #expect(!engine.supportsTrackSelection)
            #expect(engine.supportsAudioTrackSelection)
            #expect(!engine.supportsSubtitleTrackSelection)
            #expect(!engine.supportsExternalSubtitles)
            #expect(engine.seekableTimeRange == nil)
            #expect(engine.availableAudioTracks.isEmpty && engine.availableSubtitleTracks.isEmpty)
            engine.stop(); engine.stop()
            engine.play(); engine.pause(); engine.recoverFromStall()
            #expect(engine.state == .stopped)
            #expect(engine.currentTime == 0 && engine.gpuBlocks == 0)
        }
        #expect(VLCKitEngine().supportsSeeking)
        #expect(VLCKitEngine().supportsTrackSelection)
    }
}

@Suite("Live buffer startup and starvation observations")
struct LivePlaybackBufferTests {
    @Test func clockWaitsForBothStreamsAndVideoOnlyCanStart() {
        var state = LivePlaybackBufferState()
        state.enqueueVideo(end: 10.4)
        #expect(!state.canStart(at: 10))
        state.enqueueAudio(end: 10.1)
        #expect(!state.canStart(at: 10))
        state.enqueueAudio(end: 10.192)
        #expect(state.canStart(at: 10))
        var silent = LivePlaybackBufferState()
        silent.expectsAudio = false; silent.enqueueVideo(end: 10.2)
        #expect(silent.canStart(at: 10))
    }
    @Test func videoStarvationAndQueuePeaksIgnoreRepeatedPollsAndPause() {
        var state = LivePlaybackBufferState()
        state.enqueueVideo(end: 10.5); state.enqueueAudio(end: 10.25)
        state.observe(time: 10, running: true)
        #expect(state.peakAudioDepth == 0.25)
        #expect(state.peakVideoDepth == 0.5)
        state.observe(time: 11, running: false)
        #expect(state.videoStarvations == 0)
        state.observe(time: 11, running: true); state.observe(time: 12, running: true)
        #expect(state.videoStarvations == 1)
        state.enqueueVideo(end: 13); state.observe(time: 12, running: true)
        state.observe(time: 14, running: true)
        #expect(state.videoStarvations == 2)
        #expect(state.peakVideoDepth == 1)
        #expect(state.peakAudioDepth == 0.25)
    }
    @Test func starvationCountsTransitionsRatherThanEveryPollAndIgnoresPause() {
        var state = LivePlaybackBufferState()
        state.enqueueAudio(end: 1)
        state.observe(time: 2, running: false)
        #expect(state.audioStarvations == 0)
        state.observe(time: 2, running: true); state.observe(time: 3, running: true)
        #expect(state.audioStarvations == 1)
        state.enqueueAudio(end: 4); state.observe(time: 3, running: true)
        state.observe(time: 5, running: true)
        #expect(state.audioStarvations == 2)
        #expect(state.audioDepth(at: 5) == 0)
        state.resetAudio()
        #expect(state.audioEnd == nil)
        #expect(!state.canStart(at: 5))
    }
}

@Suite("Live recovery policy")
struct LiveRecoveryTests {
    @Test func retriesAreBoundedAndOnlySustainedProgressRestoresBudget() {
        var policy = LiveStreamRecoveryPolicy()
        #expect(policy.nextDelay(recoverable: false, now: 0) == nil)
        #expect(policy.nextDelay(recoverable: true, now: 1) == 0.5)
        policy.markHealthy(now: 2)
        #expect(policy.nextDelay(recoverable: true, now: 3) == 1)
        #expect(policy.nextDelay(recoverable: true, now: 4) == 2)
        #expect(policy.nextDelay(recoverable: true, now: 5) == nil)
        policy.markHealthy(now: 33)
        #expect(policy.nextDelay(recoverable: true, now: 33) == nil)
        policy.markHealthy(now: 34)
        #expect(policy.nextDelay(recoverable: true, now: 35) == 0.5)
        #expect(policy.totalAttempts == 4)
    }
    @Test func timestampJumpsAndLongPauseHaveExplicitThresholds() {
        #expect(!LiveStreamRecoveryPolicy.isTimestampDiscontinuity(previous: nil, next: 500))
        #expect(!LiveStreamRecoveryPolicy.isTimestampDiscontinuity(previous: 10, next: 10.017))
        #expect(LiveStreamRecoveryPolicy.isTimestampDiscontinuity(previous: 10, next: 0))
        #expect(LiveStreamRecoveryPolicy.isTimestampDiscontinuity(previous: 10, next: 30))
        #expect(!LiveStreamRecoveryPolicy.shouldRefreshAfterPause(began: 100, now: 114))
        #expect(LiveStreamRecoveryPolicy.shouldRefreshAfterPause(began: 100, now: 115))
    }
}

/// Exercises the production worker and AVFoundation renderers without a window,
/// Plex session or manual app launch. Physical output fidelity remains user-owned.
@Suite("MPEG-2 paced renderer recovery", .serialized)
@MainActor struct MPEG2RendererIntegrationTests {
    private func source() throws -> PlaybackSource {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(".build/metal-mpeg2/fixtures/renderer-hd.ts")
        try #require(FileManager.default.fileExists(atPath: url.path), "Run scripts/test_macos.sh to generate the renderer fixture")
        return PlaybackSource(url: url, startPosition: nil, context: .init(
            attemptID: UUID(), title: "Generated renderer fixture", ratingKey: "fixture",
            engine: .avPlayer, resolverReason: "Hosted MPEG-2 integration test", mediaID: 0,
            partID: 0, sanitizedPlaybackURL: "local generated fixture"))
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(condition(), "Renderer lifecycle transition timed out")
    }

    @Test(arguments: [ExperimentalMPEG2Mode.cpu, .metal])
    func pacedPauseRecoveryReloadAndStop(mode: ExperimentalMPEG2Mode) async throws {
        let engine = ExperimentalMPEG2Engine(mode: mode)
        defer { engine.stop() }
        let input = try source()
        engine.load(source: input)
        do {
            try await waitUntil { engine.state == .playing && engine.currentTime > 1 }
        } catch {
            print("Renderer startup: \(engine.state), \(String(describing: engine.error)), \(engine.renderingDiagnostics)")
            throw error
        }
        #expect(engine.submittedVideoFrames > 60)
        #expect(engine.outputVideoWidth == 1920 && engine.outputVideoHeight == 1080)
        #expect(engine.outputAudioChannels == 2)
        #expect(mode == .cpu ? engine.gpuBlocks == 0 : engine.gpuBlocks > 0)

        engine.pause()
        // Allow one in-flight sample to settle; paused decode must then stop
        // advancing instead of accumulating the remaining minute of media.
        try await Task.sleep(for: .seconds(1))
        let pausedFrames = engine.submittedVideoFrames
        let pausedTime = engine.currentTime
        try await Task.sleep(for: .seconds(2))
        #expect(engine.submittedVideoFrames == pausedFrames)
        #expect(abs(engine.currentTime - pausedTime) < 0.05)
        #expect(engine.buffers.peakVideoDepth < 2.1)
        #expect(engine.buffers.peakAudioDepth < 2.1)
        engine.play()
        try await waitUntil { engine.currentTime > pausedTime + 0.5 }

        let framesBeforeRecovery = engine.submittedVideoFrames
        engine.recoverFromStall()
        try await waitUntil { engine.recovery.totalAttempts == 1 && engine.state == .playing && engine.submittedVideoFrames > framesBeforeRecovery + 60 }
        #expect(engine.error == nil)
        #expect(engine.currentTime >= pausedTime)
        let recoveredTime = engine.currentTime
        try await waitUntil { engine.currentTime > recoveredTime + 10 }
        #expect(engine.recovery.totalAttempts == 1)

        engine.pause()
        try await Task.sleep(for: .seconds(1))
        let heldFrames = engine.submittedVideoFrames
        try await Task.sleep(for: .seconds(15))
        #expect(engine.submittedVideoFrames == heldFrames)
        #expect(engine.recovery.totalAttempts == 1)
        engine.play()
        try await waitUntil { engine.recovery.totalAttempts == 2 && engine.state == .playing && engine.submittedVideoFrames > heldFrames + 60 }


        // Invalidate an active worker and its asynchronous renderer flushes.
        engine.load(source: input)
        engine.load(source: input)
        try await waitUntil { engine.state == .playing && engine.currentTime > 0.5 }
        #expect(engine.recovery.totalAttempts == 0)
        #expect(engine.error == nil)
        engine.recoverFromStall()
        try await waitUntil { engine.recovery.totalAttempts == 1 }
        engine.stop()
        try await Task.sleep(for: .seconds(1)) // crosses the pending retry delay
        engine.play(); engine.recoverFromStall()
        #expect(engine.state == .stopped)
        #expect(engine.submittedVideoFrames == 0 && engine.currentTime == 0)
        #expect(engine.recovery.totalAttempts == 0)
    }
}
