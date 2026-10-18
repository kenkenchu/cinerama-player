import Foundation

struct TVPlaybackChoice: Identifiable {
    let mediaIndex: Int
    let media: PlexMedia
    let part: PlexMediaPart
    let audio: PlexStream?
    let requiresRemux: Bool
    var id: Int { mediaIndex }
    var label: String {
        let resolution = media.height.map { "\($0)p" } ?? media.videoResolution ?? "Unknown resolution"
        return "\(resolution) · \(media.videoCodec?.uppercased() ?? "Video") · \(audio?.displayTitle ?? audio?.codec?.uppercased() ?? "No audio")"
    }
}

enum TVPlaybackFailure: LocalizedError {
    case unsupported(String)
    var errorDescription: String? {
        switch self { case .unsupported(let message): message }
    }
}

/// Conservative Apple TV HD eligibility, isolated from the Mac resolver.
/// AVPlayer's actual decoder remains authoritative after metadata checks.
enum TVStreamResolver {
    static func choice(media: PlexMedia, index: Int) throws -> TVPlaybackChoice {
        guard media.parts.count == 1, let part = media.parts.first, part.isAvailable else {
            throw TVPlaybackFailure.unsupported("Missing or multi-part files are not supported in this prototype.")
        }
        let video = part.streams.first { $0.streamType == .video }
        let height = media.height ?? video?.height
        let width = media.width ?? video?.width
        let resolution = media.videoResolution?.lowercased() ?? ""
        guard height.map({ $0 <= 1080 }) ?? ["1080", "720", "576", "480", "sd"].contains(resolution),
              width.map({ $0 <= 1920 }) ?? true else {
            throw TVPlaybackFailure.unsupported("Choose a known HD version, up to 1920 × 1080. 4K playback is outside this prototype.")
        }
        let transfer = video?.colorTrc?.lowercased() ?? ""
        guard video?.doviPresent != true, video?.doviProfile == nil,
              !["smpte2084", "arib-std-b67", "pq", "hlg"].contains(transfer),
              video?.colorPrimaries?.lowercased() != "bt2020" else {
            throw TVPlaybackFailure.unsupported("Choose an SDR version. HDR/Dolby Vision conversion is outside this prototype.")
        }
        let codec = (media.videoCodec ?? video?.codec ?? "").lowercased()
        guard ["h264", "hevc"].contains(codec) else {
            throw TVPlaybackFailure.unsupported("This prototype supports H.264 and HEVC SDR. Other codecs need the future TV VLC engine.")
        }
        if codec == "h264", (video?.bitDepth ?? 8) > 8 {
            throw TVPlaybackFailure.unsupported("10-bit H.264 is not supported by this prototype.")
        }
        if let fps = video?.frameRate, fps > (codec == "hevc" ? 30.1 : 60.1) {
            throw TVPlaybackFailure.unsupported("This frame rate exceeds the Apple TV HD playback envelope.")
        }
        let audioTracks = part.streams.filter { $0.streamType == .audio }
        let compatibleAudio = audioTracks.filter {
            ["aac", "ac3", "eac3", "mp3", "alac"].contains($0.codec?.lowercased() ?? "")
        }
        let audio = compatibleAudio.first(where: { $0.isSelected == true })
            ?? compatibleAudio.first(where: { $0.isDefault == true }) ?? compatibleAudio.first
        guard audioTracks.isEmpty || audio != nil else {
            throw TVPlaybackFailure.unsupported("No compatible audio track. This prototype needs AAC, AC3, EAC3, MP3 or Apple Lossless; server audio conversion is disabled.")
        }
        let defaultAudio = audioTracks.first(where: { $0.isDefault == true }) ?? audioTracks.first
        let container = (part.container ?? media.container ?? "").lowercased()
        let requiresRemux = !["mp4", "m4v", "mov"].contains(container)
            || audio?.id != defaultAudio?.id
        return TVPlaybackChoice(mediaIndex: index, media: media, part: part,
            audio: audio, requiresRemux: requiresRemux)
    }
}
