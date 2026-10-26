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
        state.enqueueAudio(end: 10.3)
        #expect(state.canStart(at: 10))
        var silent = LivePlaybackBufferState()
        silent.expectsAudio = false; silent.enqueueVideo(end: 10.2)
        #expect(silent.canStart(at: 10))
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
