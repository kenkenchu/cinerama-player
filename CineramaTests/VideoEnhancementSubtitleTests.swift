import Foundation
import Testing
@testable import Cinerama

@Suite("Video enhancement subtitle eligibility")
struct VideoEnhancementSubtitleTests {
    @Test(arguments: [VideoEnhancementMode.automatic, .enabled, .disabled])
    func embeddedTracksDoNotOverrideThePreference(mode: VideoEnhancementMode) throws {
        // Includes a Plex-selected/default/forced track: metadata alone does
        // not say what the local engine is actually displaying.
        let media = try mediaWithStreams(#"""
            {"id":2,"streamType":1,"codec":"h264","width":1280,"height":720,"frameRate":24},
            {"id":3,"streamType":3,"codec":"mov_text","selected":true,"default":true,"forced":true},
            {"id":4,"streamType":3,"codec":"pgs"}
            """#)
        let request = VideoEnhancementRequest.make(mode: mode, media: media, part: media.parts[0])
        #expect(request.mode == mode)
        #expect(request.disabledReason == nil)
        #expect(request.sourceWidth == 1280)
        #expect(request.sourceHeight == 720)
        #expect(request.frameRate == 24)
    }

    @Test func sidecarTracksDoNotDisableEnhancement() throws {
        let media = try mediaWithStreams(#"""
            {"id":3,"streamType":3,"codec":"srt","key":"/library/streams/3","selected":true}
            """#)
        let request = VideoEnhancementRequest.make(mode: .enabled, media: media, part: media.parts[0])
        #expect(request.isPotentiallyEnabled)
        #expect(request.disabledReason == nil)
    }

    @Test(arguments: [VideoEnhancementMode.automatic, .enabled])
    func avPlayerRequiresNativeRenderingOnlyWhileSubtitlesAreSelected(mode: VideoEnhancementMode) throws {
        let request = VideoEnhancementRequest(mode: mode)
        #expect(request.nativeSubtitleRenderingStatus(engine: .avPlayer, hasSelectedSubtitle: false) == nil)
        let status = try #require(request.nativeSubtitleRenderingStatus(engine: .avPlayer, hasSelectedSubtitle: true))
        #expect(status.state == .disabled)
        #expect(status.reason == "Native AVPlayer renderer required while subtitles are selected")
        // The request survives the temporary native-renderer fallback, so Off
        // in the subtitle picker immediately makes enhancement eligible again.
        #expect(request.nativeSubtitleRenderingStatus(engine: .avPlayer, hasSelectedSubtitle: false) == nil)
        #expect(request.mode == mode)
    }

    @Test(arguments: [false, true])
    func vlcCompositedSubtitlesRemainEligible(isSelected: Bool) {
        let request = VideoEnhancementRequest(mode: .enabled)
        #expect(request.nativeSubtitleRenderingStatus(engine: .vlcKit, hasSelectedSubtitle: isSelected) == nil)
        #expect(request.isPotentiallyEnabled)
    }

    @Test func explicitOffStillReportsThePreference() {
        let request = VideoEnhancementRequest.disabled
        #expect(request.nativeSubtitleRenderingStatus(engine: .avPlayer, hasSelectedSubtitle: true) == nil)
        #expect(request.nonRenderingStatus == .disabled)
    }

    @Test func hdrAndFrameRateLimitsKeepTheirOwnReasons() throws {
        let media = try mediaWithStreams(#"""
            {"id":2,"streamType":1,"codec":"hevc","bitDepth":10,"frameRate":24},
            {"id":3,"streamType":3,"codec":"pgs"}
            """#)
        let hdrRequest = VideoEnhancementRequest.make(mode: .automatic, media: media, part: media.parts[0])
        let requests = [
            hdrRequest,
            VideoEnhancementRequest(mode: .automatic, frameRate: 60),
            VideoEnhancementRequest(mode: .enabled, frameRate: 120),
        ]
        let reasons = ["Auto skips HDR", "Auto skips >50fps", "Disabled above 70fps"]
        for (request, reason) in zip(requests, reasons) {
            #expect(request.nativeSubtitleRenderingStatus(engine: .avPlayer, hasSelectedSubtitle: true) == nil)
            #expect(request.nonRenderingStatus.state == .unavailable)
            #expect(request.nonRenderingStatus.reason == reason)
        }
    }

    @Test(arguments: [VideoEnhancementMode.automatic, .enabled])
    func sdrEmbeddedSubtitleEngineChoiceIsTVOnly(mode: VideoEnhancementMode) throws {
        let media = try engineSelectionMedia(videoFields: #","bitDepth":8"#)
        let decision = directDecision(media, mode: mode, subtitleID: 3)
        #expect(decision.engine == .avPlayer)
        #expect(!decision.usesEnhancedSubtitleRenderer)
    }

    @Test func subtitleOffAndDisabledEnhancementKeepTheNormalEngine() throws {
        let media = try engineSelectionMedia(videoFields: #","bitDepth":8"#)
        // Metadata says selected/default/forced, but an actual Off choice wins.
        for subtitleID: Int? in [nil, 999] {
            let decision = directDecision(media, mode: .enabled, subtitleID: subtitleID)
            #expect(decision.engine == .avPlayer)
            #expect(!decision.usesEnhancedSubtitleRenderer)
        }
        #expect(directDecision(media, mode: .disabled, subtitleID: 3).engine == .avPlayer)
        #expect(directDecision(media, mode: .automatic, subtitleID: 4).engine == .vlcKit)
    }

    @Test func unusedIncompatibleTracksDoNotChooseTheEngine() throws {
        let media = try mediaWithStreams(#"""
            {"id":2,"streamType":1,"codec":"h264","bitDepth":8},
            {"id":10,"streamType":2,"codec":"aac","default":true},
            {"id":11,"streamType":2,"codec":"dts"},
            {"id":12,"streamType":3,"codec":"ass"},
            {"id":13,"streamType":3,"codec":"mov_text"}
            """#)
        func resolve(audio: Int, subtitle: Int?) -> PlaybackEngineType {
            StreamResolver.evaluateForDirectPlayback(
                media: media, part: media.parts[0], enhancementMode: .automatic,
                selectedSubtitleStreamID: subtitle, selectedAudioStreamID: audio
            ).engine
        }
        #expect(resolve(audio: 10, subtitle: nil) == .avPlayer)
        #expect(resolve(audio: 10, subtitle: 13) == .avPlayer)
        #expect(resolve(audio: 11, subtitle: nil) == .vlcKit)
        #expect(resolve(audio: 10, subtitle: 12) == .vlcKit)
        // Returning to compatible tracks makes native playback eligible again.
        #expect(resolve(audio: 10, subtitle: nil) == .avPlayer)
    }

    @Test(arguments: [
        #","bitDepth":10"#,
        #","colorTrc":"smpte2084""#,
        #","bitDepth":8,"colorTrc":"arib-std-b67""#,
        #","bitDepth":8,"profile":"HDR10+""#,
        #","bitDepth":8,"colorPrimaries":"bt2020""#,
        #","bitDepth":8,"DOVIPresent":true"#,
        #","bitDepth":8,"DOVIProfile":5"#,
        #","bitDepth":8,"DOVIProfile":7"#,
        #","bitDepth":8,"DOVIProfile":8,"DOVIBLCompatID":1"#,
        #","bitDepth":8,"DOVIProfile":8,"DOVIBLCompatID":4"#,
        #","bitDepth":8,"DOVIBLCompatID":1"#,
        #","bitDepth":8,"DOVILevel":6"#,
        "", // Missing video range metadata must not be assumed SDR.
    ])
    func hdrDolbyVisionAndUnknownRangeNeverGetTheOverride(videoFields: String) throws {
        let media = try engineSelectionMedia(videoFields: videoFields)
        for mode: VideoEnhancementMode in [.automatic, .enabled] {
            let decision = directDecision(media, mode: mode, subtitleID: 3)
            #expect(decision.engine == .avPlayer)
            #expect(!decision.usesEnhancedSubtitleRenderer)
        }
    }

    @Test func sdrTransferCanEstablishRangeWithoutBitDepth() throws {
        let media = try engineSelectionMedia(videoFields: #","colorTrc":"bt709""#)
        let decision = directDecision(media, mode: .enabled, subtitleID: 3)
        #expect(decision.engine == .avPlayer)
    }

    @Test func sdrContainersThatNeedVLCCanAlsoPreferEnhancementOverTheAtmosRemux() throws {
        let media = try engineSelectionMedia(videoFields: #","bitDepth":8"#, container: "mkv")
        let decision = directDecision(media, mode: .enabled, subtitleID: 3)
        #expect(decision.engine == .vlcKit)
        #expect(!decision.usesEnhancedSubtitleRenderer)
        let hdr = try engineSelectionMedia(videoFields: #","colorTrc":"smpte2084""#, container: "mkv")
        #expect(!directDecision(hdr, mode: .enabled, subtitleID: 3).usesEnhancedSubtitleRenderer)
    }

    @Test func frameRateLimitsAndExplicitEngineOverridesStillWin() throws {
        let media = try engineSelectionMedia(videoFields: #","bitDepth":8,"frameRate":120"#)
        #expect(directDecision(media, mode: .enabled, subtitleID: 3).engine == .avPlayer)
        let autoSkipped = try engineSelectionMedia(videoFields: #","bitDepth":8,"frameRate":60"#)
        #expect(directDecision(autoSkipped, mode: .automatic, subtitleID: 3).engine == .avPlayer)
        let sdr = try engineSelectionMedia(videoFields: #","bitDepth":8"#)
        let forcedAV = StreamResolver.evaluateForDirectPlayback(
            media: sdr, part: sdr.parts[0], enhancementMode: .enabled,
            selectedSubtitleStreamID: 3, forceAVPlayer: true
        )
        #expect(forcedAV.engine == .avPlayer)
        #expect(!forcedAV.usesEnhancedSubtitleRenderer)
        let forcedVLC = StreamResolver.evaluateForDirectPlayback(
            media: sdr, part: sdr.parts[0], enhancementMode: .disabled,
            selectedSubtitleStreamID: nil, forceVLCKit: true
        )
        #expect(forcedVLC.engine == .vlcKit)
        #expect(!forcedVLC.usesEnhancedSubtitleRenderer)
    }

    private func directDecision(
        _ media: PlexMedia, mode: VideoEnhancementMode, subtitleID: Int?
    ) -> StreamResolver.Decision {
        StreamResolver.evaluateForDirectPlayback(
            media: media, part: media.parts[0], enhancementMode: mode,
            selectedSubtitleStreamID: subtitleID
        )
    }

    private func engineSelectionMedia(videoFields: String, container: String = "mp4") throws -> PlexMedia {
        try JSONDecoder().decode(PlexMedia.self, from: Data("""
            {"id":1,"container":"\(container)","videoCodec":"h264","audioCodec":"aac","Part":[
              {"id":1,"key":"/clip.mp4","Stream":[
                {"id":2,"streamType":1,"codec":"h264"\(videoFields)},
                {"id":10,"streamType":2,"codec":"aac","channels":2,"default":true},
                {"id":11,"streamType":2,"codec":"ac3","channels":6},
                {"id":3,"streamType":3,"codec":"mov_text","selected":true,"default":true,"forced":true},
                {"id":4,"streamType":3,"codec":"srt","key":"/library/streams/4"}
              ]}
            ]}
            """.utf8))
    }


    private func mediaWithStreams(_ streams: String) throws -> PlexMedia {
        try JSONDecoder().decode(PlexMedia.self, from: Data("""
            {"id":1,"container":"mp4","videoCodec":"h264","audioCodec":"aac","Part":[{"id":1,"key":"/clip","Stream":[\(streams)]}]}
            """.utf8))
    }
}
