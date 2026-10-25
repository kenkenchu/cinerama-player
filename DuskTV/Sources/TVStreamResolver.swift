import Foundation

struct TVPlaybackChoice: Identifiable {
    let mediaIndex: Int
    let media: PlexMedia
    let part: PlexMediaPart
    let audio: PlexStream?
    let subtitle: PlexStream?
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
    static func supportsSubtitle(_ stream: PlexStream) -> Bool {
        stream.streamType == .subtitle && ["srt", "subrip", "webvtt", "vtt", "ass", "ssa", "mov_text", "tx3g", "text"]
            .contains(stream.codec?.lowercased() ?? "")
    }

    static func supportsAudio(_ stream: PlexStream) -> Bool {
        stream.streamType == .audio && ["aac", "ac3", "eac3", "mp3", "alac"].contains(stream.codec?.lowercased() ?? "")
    }

    static func choice(media: PlexMedia, index: Int, subtitleID: Int? = nil, audioID: Int? = nil) throws -> TVPlaybackChoice {
        guard media.parts.count == 1, let part = media.parts.first, part.isAvailable else {
            throw TVPlaybackFailure.unsupported("Missing or multi-part files are not supported in this TV version.")
        }
        let video = part.streams.first { $0.streamType == .video }
        let resolutionLabel = media.videoResolution?.lowercased() ?? ""
        if resolutionLabel.contains("4k") || resolutionLabel.contains("uhd")
            || [media.height, video?.height].compactMap({ $0 }).contains(where: { $0 >= 2160 })
            || [media.width, video?.width].compactMap({ $0 }).contains(where: { $0 >= 3840 }) {
            throw TVPlaybackFailure.unsupported("4K video is not supported on this Apple TV HD. Choose an HD version of this title. Cinerama does not downscale 4K or ask Plex to convert it.")
        }
        if [media.height, video?.height].compactMap({ $0 }).contains(where: { $0 > 1080 })
            || [media.width, video?.width].compactMap({ $0 }).contains(where: { $0 > 1920 }) {
            throw TVPlaybackFailure.unsupported("This video exceeds the Apple TV HD 1080p limit. Choose an HD version.")
        }
        let height = media.height ?? video?.height
        let width = media.width ?? video?.width
        let resolution = media.videoResolution?.lowercased() ?? ""
        guard height.map({ $0 <= 1080 }) ?? ["1080", "720", "576", "480", "sd"].contains(resolution),
              width.map({ $0 <= 1920 }) ?? true else {
            throw TVPlaybackFailure.unsupported("Choose a known HD version, up to 1920 × 1080. 4K playback is outside this TV version.")
        }
        let transfer = video?.colorTrc?.lowercased() ?? ""
        guard video?.doviPresent != true, video?.doviProfile == nil,
              !["smpte2084", "arib-std-b67", "pq", "hlg"].contains(transfer),
              video?.colorPrimaries?.lowercased() != "bt2020" else {
            throw TVPlaybackFailure.unsupported("Choose an SDR version. HDR/Dolby Vision conversion is outside this TV version.")
        }
        let codec = (media.videoCodec ?? video?.codec ?? "").lowercased()
        guard ["h264", "hevc"].contains(codec) else {
            throw TVPlaybackFailure.unsupported("This TV version supports H.264 and HEVC SDR. Other codecs need the future TV VLC engine.")
        }
        if codec == "h264", (video?.bitDepth ?? 8) > 8 {
            throw TVPlaybackFailure.unsupported("10-bit H.264 is not supported by this TV version.")
        }
        if let fps = video?.frameRate, fps > (codec == "hevc" ? 30.1 : 60.1) {
            throw TVPlaybackFailure.unsupported("This frame rate exceeds the Apple TV HD playback envelope.")
        }
        let audioTracks = part.streams.filter { $0.streamType == .audio }
        let compatibleAudio = audioTracks.filter(supportsAudio)
        if let audioID, !compatibleAudio.contains(where: { $0.id == audioID }) {
            throw TVPlaybackFailure.unsupported("This audio track cannot play locally on Apple TV HD. Choose a compatible track; server audio conversion is disabled.")
        }
        let audio = compatibleAudio.first(where: { $0.id == audioID })
            ?? compatibleAudio.first(where: { $0.isSelected == true })
            ?? compatibleAudio.first(where: { $0.isDefault == true }) ?? compatibleAudio.first
        guard audioTracks.isEmpty || audio != nil else {
            throw TVPlaybackFailure.unsupported("No compatible audio track. This TV version needs AAC, AC3, EAC3, MP3 or Apple Lossless; server audio conversion is disabled.")
        }
        let defaultAudio = audioTracks.first(where: { $0.isDefault == true }) ?? audioTracks.first
        let container = (part.container ?? media.container ?? "").lowercased()
        let subtitle = subtitleID.flatMap { id in part.streams.first { $0.id == id && $0.streamType == .subtitle } }
        if subtitleID != nil && subtitle.map({ !supportsSubtitle($0) }) != false {
            throw TVPlaybackFailure.unsupported("This subtitle format is unavailable in the TV version. Choose a text subtitle or Off. Subtitle burning and server video conversion are disabled.")
        }
        let requiresRemux = !["mp4", "m4v", "mov"].contains(container)
            || audio?.id != defaultAudio?.id || subtitle != nil
        return TVPlaybackChoice(mediaIndex: index, media: media, part: part,
            audio: audio, subtitle: subtitle, requiresRemux: requiresRemux)
    }
}
