import Foundation
import Testing
@testable import CineramaTV

@Suite("Apple TV HD stream eligibility")
struct TVStreamResolverTests {
    @Test func compatibleMP4StartsDirect() throws {
        let choice = try TVStreamResolver.choice(media: TVTestFixtures.media(), index: 0)
        #expect(!choice.requiresRemux)
        #expect(choice.audio?.id == 2)
        #expect(choice.subtitle == nil)
    }

    @Test(arguments: ["mkv", "avi", "mpegts"])
    func otherContainersRequireRemux(container: String) throws {
        let media = try TVTestFixtures.media(fields: ["container": container])
        #expect(try TVStreamResolver.choice(media: media, index: 0).requiresRemux)
    }

    @Test func selectedAudioAndTextSubtitleRequireRemux() throws {
        var other = TVTestFixtures.audio
        other["id"] = 4
        other["codec"] = "ac3"
        other["default"] = false
        let media = try TVTestFixtures.media(tracks: [TVTestFixtures.audio, other, TVTestFixtures.subtitle])
        let audio = try TVStreamResolver.choice(media: media, index: 0, audioID: 4)
        #expect(audio.requiresRemux)
        #expect(audio.audio?.id == 4)
        let subtitle = try TVStreamResolver.choice(media: media, index: 0, subtitleID: 3)
        #expect(subtitle.requiresRemux)
        #expect(subtitle.subtitle?.id == 3)
        #expect(try TVStreamResolver.choice(media: media, index: 0).subtitle == nil)
    }

    @Test(arguments: ["4k", "uhd"])
    func resolutionLabelsRejectUHD(label: String) throws {
        try rejects(TVTestFixtures.media(fields: ["videoResolution": label]), containing: "4K")
    }

    @Test func streamDimensionsCannotHideBehindHDMediaMetadata() throws {
        try rejects(TVTestFixtures.media(video: ["width": 3840, "height": 2160]), containing: "4K")
        try rejects(TVTestFixtures.media(video: ["width": 2560, "height": 1440]), containing: "1080p")
    }

    @Test(arguments: ["smpte2084", "arib-std-b67", "pq", "hlg"])
    func HDRTransferFunctionsAreRejected(transfer: String) throws {
        try rejects(TVTestFixtures.media(video: ["colorTrc": transfer]), containing: "SDR")
    }

    @Test func dolbyVisionAndWideGamutAreRejected() throws {
        try rejects(TVTestFixtures.media(video: ["DOVIPresent": true]), containing: "SDR")
        try rejects(TVTestFixtures.media(video: ["DOVIProfile": 7]), containing: "SDR")
        try rejects(TVTestFixtures.media(video: ["colorPrimaries": "bt2020"]), containing: "SDR")
    }

    @Test func unsupportedVideoAndFrameRatesAreRejected() throws {
        try rejects(TVTestFixtures.media(fields: ["videoCodec": "av1"]), containing: "H.264")
        try rejects(TVTestFixtures.media(video: ["bitDepth": 10]), containing: "10-bit H.264")
        try rejects(TVTestFixtures.media(video: ["frameRate": 120]), containing: "frame rate")
        try rejects(TVTestFixtures.media(video: ["codec": "hevc", "frameRate": 60],
                                        fields: ["videoCodec": "hevc"]), containing: "frame rate")
    }

    @Test func unusedUnsupportedAudioDoesNotBlockCompatibleChoice() throws {
        var unsupported = TVTestFixtures.audio
        unsupported["id"] = 8
        unsupported["codec"] = "truehd"
        let media = try TVTestFixtures.media(tracks: [TVTestFixtures.audio, unsupported])
        #expect(try TVStreamResolver.choice(media: media, index: 0).audio?.id == 2)
        do {
            _ = try TVStreamResolver.choice(media: media, index: 0, audioID: 8)
            Issue.record("Unsupported audio must not request conversion")
        } catch { #expect(error.localizedDescription.contains("conversion is disabled")) }
        try rejects(TVTestFixtures.media(tracks: [unsupported]), containing: "No compatible audio")
    }

    @Test func bitmapOrMissingSubtitleCannotBeSelected() throws {
        var bitmap = TVTestFixtures.subtitle
        bitmap["codec"] = "pgs"
        let media = try TVTestFixtures.media(tracks: [TVTestFixtures.audio, bitmap])
        for id in [3, 999] {
            do {
                _ = try TVStreamResolver.choice(media: media, index: 0, subtitleID: id)
                Issue.record("Unavailable subtitle must not burn into video")
            } catch { #expect(error.localizedDescription.contains("Subtitle burning")) }
        }
    }

    @Test func missingAndMultipartMediaFailClosed() throws {
        try rejects(TVTestFixtures.media(partFields: ["exists": false]), containing: "Missing")
        try rejects(TVTestFixtures.media(fields: ["Part": []]), containing: "Missing")
        let part: [String: Any] = ["id": 1, "key": "/file.mp4"]
        try rejects(TVTestFixtures.media(fields: ["Part": [part, part]]), containing: "multi-part")
    }

    @Test func preferredVersionSkipsUHDAndUnavailableVersions() throws {
        let version: [String: Any] = ["id": 2, "container": "mp4", "height": 720, "width": 1280,
                                     "videoCodec": "h264", "Part": [["id": 2, "key": "/hd.mp4"]]]
        var uhd = version
        uhd["height"] = 2160
        uhd["width"] = 3840
        var unavailable = version
        unavailable["Part"] = [["id": 3, "key": "/missing.mp4", "exists": false]]
        let details = try TVTestFixtures.details(media: [uhd, unavailable, version])
        let choice = try TVStreamResolver.preferredChoice(details: details, profile: nil)
        #expect(choice.mediaIndex == 2)
        #expect(choice.media.height == 720)
    }

    private func rejects(_ media: PlexMedia, containing message: String) throws {
        do {
            _ = try TVStreamResolver.choice(media: media, index: 0)
            Issue.record("Unsupported media was accepted: \(message)")
        } catch { #expect(error.localizedDescription.contains(message)) }
    }
}
