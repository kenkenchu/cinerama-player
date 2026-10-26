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
