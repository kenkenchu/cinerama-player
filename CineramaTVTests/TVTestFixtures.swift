import Foundation
@testable import CineramaTV

enum TVTestFixtures {
    static var audio: [String: Any] { [
        "id": 2, "streamType": 2, "codec": "aac", "channels": 2,
        "default": true, "languageCode": "eng", "displayTitle": "English"
    ] }
    static var subtitle: [String: Any] { [
        "id": 3, "streamType": 3, "codec": "srt", "languageCode": "eng",
        "displayTitle": "English", "key": "/library/streams/3"
    ] }

    static func media(video: [String: Any] = [:], fields: [String: Any] = [:],
                      partFields: [String: Any] = [:], tracks: [[String: Any]]? = nil) throws -> PlexMedia {
        var videoStream: [String: Any] = [
            "id": 1, "streamType": 1, "codec": "h264", "width": 1920,
            "height": 1080, "bitDepth": 8, "frameRate": 24, "colorTrc": "bt709"
        ]
        videoStream.merge(video) { _, new in new }
        var part: [String: Any] = ["id": 1, "key": "/library/parts/1/file.mp4",
                                   "Stream": [videoStream] + (tracks ?? [audio])]
        part.merge(partFields) { _, new in new }
        var payload: [String: Any] = ["id": 1, "container": "mp4", "videoCodec": "h264",
                                      "width": 1920, "height": 1080, "Part": [part]]
        payload.merge(fields) { _, new in new }
        return try decode(PlexMedia.self, payload)
    }

    static func details(server: String? = "server-a", ratingKey: String = "1",
                        type: String = "movie", series: String? = nil,
                        media: [[String: Any]] = []) throws -> PlexMediaDetails {
        var payload: [String: Any] = ["ratingKey": ratingKey, "key": "/library/metadata/\(ratingKey)",
                                     "title": "Test title", "type": type, "Media": media]
        if let series { payload["grandparentRatingKey"] = series }
        return try decode(PlexMediaDetails.self, payload, server: server)
    }

    static func stream(_ fields: [String: Any]) throws -> PlexStream {
        try decode(PlexStream.self, fields)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ payload: [String: Any],
                                      server: String? = "server-a") throws -> T {
        let decoder = JSONDecoder()
        decoder.userInfo[.cineramaServerID] = server
        return try decoder.decode(type, from: JSONSerialization.data(withJSONObject: payload))
    }
}
