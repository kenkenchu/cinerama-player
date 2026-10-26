import AVFoundation
import CineramaMPEG2
import Foundation
import Testing
@testable import CineramaTV

@Suite("TV experimental Live TV policy")
@MainActor struct TVLivePlaybackTests {
    private func tune(fields: [String: Any] = [:], video: [String: Any] = [:], decisions: PlexService.TranscodeStreamDecisions? = nil,
                      remux: Bool = false) throws -> PlexLiveTuneResult {
        var metadata: [String: Any] = ["videoCodec": "mpeg2video"]
        metadata.merge(fields) { _, new in new }
        let media = try TVTestFixtures.media(video: video, fields: metadata)
        return .init(serverID: "server-a", sessionID: "live", playbackSessionIdentifier: "playback",
            transcodeSessionID: remux ? "remux" : nil, playbackURL: URL(fileURLWithPath: "/fixture.ts"),
            media: media, part: media.parts[0], serverDecisions: decisions)
    }
    @Test func refusesUHDAndOtherCodecs() throws {
        try TVLivePlayback.validate(tune())
        for fields: [String: Any] in [["width": 3840], ["height": 2160], ["videoCodec": "hevc"]] {
            #expect(throws: TVPlaybackFailure.self) { try TVLivePlayback.validate(tune(fields: fields)) }
        }
    }
    @Test func streamMetadataCannotHideUHDOrHDR() throws {
        for video: [String: Any] in [["width": 3840], ["height": 1440], ["bitDepth": 10],
                                    ["colorTrc": "smpte2084"], ["colorPrimaries": "bt2020"]] {
            #expect(throws: TVPlaybackFailure.self) { try TVLivePlayback.validate(tune(video: video)) }
        }
        #expect(throws: TVPlaybackFailure.self) { try TVLivePlayback.validate(tune(fields: ["videoResolution": "4k"])) }
    }
    @Test func remuxRequiresBothCopyDecisions() throws {
        let copy = PlexService.TranscodeStreamDecisions(container: "mpegts", videoDecision: "copy",
            videoCodec: "mpeg2video", audioDecision: "copy", audioCodec: "ac3",
            subtitleDecision: nil, subtitleLocation: nil)
        try TVLivePlayback.validate(tune(decisions: copy, remux: true))
        #expect(throws: TVPlaybackFailure.self) { try TVLivePlayback.validate(tune(remux: true)) }
        for value: String? in [nil, "transcode", "directplay"] {
            var video = copy; video.videoDecision = value
            #expect(throws: TVPlaybackFailure.self) { try TVLivePlayback.validate(tune(decisions: video, remux: true)) }
            var audio = copy; audio.audioDecision = value
            #expect(throws: TVPlaybackFailure.self) { try TVLivePlayback.validate(tune(decisions: audio, remux: true)) }
        }
    }
    @Test func tuneCompletingAfterDismissalIsReleasedWithoutPlayback() async throws {
        var pending: CheckedContinuation<PlexLiveTuneResult, any Error>?
        var released: [String] = []
        let session = TVLivePlayback(service: PlexService(), mode: .cpu,
            tuneChannel: { _, _, _ in try await withCheckedThrowingContinuation { pending = $0 } },
            releaseTune: {
                #expect(!Task.isCancelled)
                released.append($0.sessionID)
            })
        let provider = PlexLiveTVProvider(identifier: "fixture", providerIdentifier: "fixture", title: "Fixture", dvrID: 1, gridKey: "fixture")
        let channel = try TVTestFixtures.decode(PlexLiveChannel.self, ["id": "1", "title": "Fixture"])
        let task = Task { await session.start(provider: provider, channel: channel, serverID: "fixture") }
        while pending == nil { await Task.yield() }
        session.togglePause()
        #expect(!session.wantsPlayback)
        session.setForeground(false)
        session.setForeground(true)
        #expect(!session.wantsPlayback) // A late tune must inherit paused intent.
        await session.finish()
        task.cancel()
        pending?.resume(returning: try tune())
        await task.value
        #expect(released == ["live"])
        #expect(session.engine.state == .stopped)
        #expect(session.engine.submittedVideoFrames == 0)
    }
    @Test func stoppedSessionCannotTuneOrRestart() async throws {
        let session = TVLivePlayback(service: PlexService(), mode: .cpu)
        await session.finish(); await session.finish()
        let provider = PlexLiveTVProvider(identifier: "fixture", providerIdentifier: "fixture", title: "Fixture", dvrID: 1, gridKey: "fixture")
        let channel = try TVTestFixtures.decode(PlexLiveChannel.self, ["id": "1", "title": "Fixture"])
        await session.start(provider: provider, channel: channel, serverID: "fixture")
        session.togglePause(); session.setForeground(true)
        #expect(!session.started)
        #expect(session.stopped)
        #expect(session.engine.state == .stopped)
        #expect(session.engine.supportsSeeking == false)
        #expect(session.engine.availableSubtitleTracks.isEmpty)
    }
}

/// Real tvOS framework/worker/renderers, no Plex connection or player screen.
@Suite("TV MPEG-2 CPU and Metal renderer", .serialized)
@MainActor struct TVMPEG2RendererTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(condition(), "TV renderer transition timed out")
    }
    @Test(arguments: [ExperimentalMPEG2Mode.cpu, .metal])
    func pacedPlaybackPauseReconnectAndRetiredWorker(mode: ExperimentalMPEG2Mode) async throws {
        let fixture = try #require(Bundle(for: TVFixtureBundle.self).url(forResource: "renderer-hd", withExtension: "ts"))
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)
        let engine = ExperimentalMPEG2Engine(mode: mode)
        defer { engine.stop(); try? AVAudioSession.sharedInstance().setActive(false) }
        engine.load(url: fixture)
        do { try await waitUntil { engine.state == .playing && engine.currentTime > 1 } }
        catch { print("TV renderer: \(engine.state), \(String(describing: engine.error)), \(engine.renderingDiagnostics)"); throw error }
        #expect(engine.outputVideoWidth == 1920 && engine.outputVideoHeight == 1080)
        #expect(engine.outputVideoCadence > 59 && engine.outputVideoCadence < 61)
        #expect(engine.outputAudioChannels == 2)
        #expect(mode == .metal ? engine.gpuBlocks > 0 : engine.gpuBlocks == 0)
        engine.pause()
        try await Task.sleep(for: .seconds(1))
        let frames = engine.submittedVideoFrames
        let time = engine.currentTime
        try await Task.sleep(for: .seconds(1))
        #expect(engine.submittedVideoFrames == frames)
        #expect(abs(engine.currentTime - time) < 0.05)
        #expect(engine.buffers.peakVideoDepth < 2.1 && engine.buffers.peakAudioDepth < 2.1)
        engine.play()
        try await waitUntil { engine.currentTime > time + 0.5 }
        engine.recoverFromStall()
        try await waitUntil { engine.recovery.totalAttempts == 1 && engine.state == .playing && engine.submittedVideoFrames > frames + 60 }
        #expect(engine.error == nil)
        engine.load(url: fixture); engine.load(url: fixture)
        try await waitUntil { engine.state == .playing && engine.currentTime > 0.5 }
        engine.recoverFromStall()
        engine.stop()
        try await Task.sleep(for: .seconds(1))
        engine.play(); engine.pause(); engine.recoverFromStall()
        #expect(engine.state == .stopped)
        #expect(engine.gpuBlocks == 0 && engine.submittedVideoFrames == 0)
    }
}
private final class TVFixtureBundle: NSObject {}

// Direct native checks do not open an audio output device. They remain useful
// when a workstation's output driver prevents simulator renderer startup.
@Suite("TV native MPEG-2 CPU/Metal samples", .serialized)
struct TVMPEG2NativeTests {
    @Test func videoFidelityPCMAndActualGPUExecution() throws {
        let fixture = try #require(Bundle(for: TVFixtureBundle.self).url(forResource: "renderer-hd", withExtension: "ts"))
        let cpu = try decode(fixture, metal: false)
        let metal = try decode(fixture, metal: true)
        #expect(cpu.pixels.count == metal.pixels.count)
        var squaredError = 0.0
        var maxError = 0
        for (a, b) in zip(cpu.pixels, metal.pixels) {
            let delta = abs(Int(a) - Int(b))
            maxError = max(maxError, delta)
            squaredError += Double(delta * delta)
        }
        let mse = squaredError / Double(cpu.pixels.count)
        let psnr = mse > 0 ? 10 * log10(255 * 255 / mse) : Double.infinity
        #expect(maxError <= 12 && psnr > 45)
        #expect(cpu.audio > 0 && cpu.audio == metal.audio)
    }

    private func decode(_ fixture: URL, metal: Bool) throws -> (pixels: [UInt8], audio: Int) {
        let decoder = try #require(cm2_create(metal ? 1 : 0))
        defer { cm2_close(decoder) }
        try #require(cm2_open(decoder, fixture.path) == 0)
        var video = 0, audio = 0
        var pixels: [UInt8] = []
        var previous: Double?
        while video < 3 {
            var kind: Int32 = 0
            let sample = try #require(cm2_next(decoder, &kind))
            if kind == 1 {
                let image = try #require(CMSampleBufferGetImageBuffer(sample))
                #expect(CVPixelBufferGetWidth(image) == 1920 && CVPixelBufferGetHeight(image) == 1080)
                let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if let previous { #expect(abs(pts - previous - 1 / 60.0) < 0.0001) }
                previous = pts
                CVPixelBufferLockBaseAddress(image, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
                for plane in 0..<CVPixelBufferGetPlaneCount(image) {
                    let bytes = try #require(CVPixelBufferGetBaseAddressOfPlane(image, plane))
                    let rows = CVPixelBufferGetHeightOfPlane(image, plane)
                    let stride = CVPixelBufferGetBytesPerRowOfPlane(image, plane)
                    let width = CVPixelBufferGetWidthOfPlane(image, plane) * (plane == 0 ? 1 : 2)
                    for row in 0..<rows {
                        pixels.append(contentsOf: UnsafeBufferPointer(start: bytes.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self), count: width))
                    }
                }
                video += 1
            } else if kind == 2 {
                audio += 1
                let format = try #require(CMSampleBufferGetFormatDescription(sample))
                let pcm = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format))
                #expect(pcm.pointee.mChannelsPerFrame == 2 && pcm.pointee.mSampleRate == 48000)
            }
        }
        #expect(metal ? cm2_gpu_blocks(decoder) > 0 : cm2_gpu_blocks(decoder) == 0)
        return (pixels, audio)
    }
}
