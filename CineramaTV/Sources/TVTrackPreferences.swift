import Foundation

/// Device-local choices, scoped by Plex profile, server and movie/series.
/// Track IDs are session-specific; save semantic properties for other episodes.
enum TVTrackPreferences {
    private struct Track: Codable {
        let off: Bool
        let language: String?
        let title: String?
        let codec: String?
        let forced: Bool
        let hearingImpaired: Bool

        init(_ stream: PlexStream?) {
            off = stream == nil
            language = (stream?.languageTag ?? stream?.languageCode)?.lowercased()
            title = stream?.displayTitle
            codec = stream?.codec
            forced = stream?.isForced == true
            hearingImpaired = stream?.isHearingImpaired == true
        }

        func matching(_ streams: [PlexStream]) -> PlexStream? {
            guard !off else { return nil }
            let candidates = streams.filter {
                (language != nil
                    ? ($0.languageTag ?? $0.languageCode)?.lowercased() == language
                    : $0.displayTitle == title)
                    && ($0.isForced == true) == forced
                    && ($0.isHearingImpaired == true) == hearingImpaired
            }
            return candidates.first { $0.displayTitle == title && $0.codec == codec }
                ?? candidates.first { $0.codec == codec } ?? candidates.first
        }
    }

    private static func key(details: PlexMediaDetails, profile: String?, kind: String) -> String? {
        guard let profile, let server = details.serverID else { return nil }
        let item: String
        if details.type == .episode {
            guard let series = details.grandparentRatingKey else { return nil }
            item = "series:\(series)"
        } else { item = "\(details.type.rawValue):\(details.ratingKey)" }
        guard let data = try? JSONEncoder().encode([profile, server, item, kind]) else { return nil }
        return "tv.track.v1." + data.base64EncodedString()
    }

    static func remember(_ stream: PlexStream?, kind: String, details: PlexMediaDetails, profile: String?, defaults: UserDefaults = .standard) {
        guard let key = key(details: details, profile: profile, kind: kind),
              let data = try? JSONEncoder().encode(Track(stream)) else { return }
        defaults.set(data, forKey: key)
    }

    /// Library playback defaults to an available full text subtitle. Plex's
    /// explicit selection wins; remembered Off remains authoritative.
    static func subtitleSelection(streams: [PlexStream], details: PlexMediaDetails?, profile: String?, defaults: UserDefaults = .standard) -> Int? {
        let tracks = streams.filter(TVStreamResolver.supportsSubtitle)
        if let details, let saved = selection(kind: "subtitle", streams: tracks,
            details: details, profile: profile, defaults: defaults) {
            return saved
        }
        return tracks.first { $0.isSelected == true }?.id
            ?? tracks.first { $0.isDefault == true && $0.isForced != true }?.id
            ?? tracks.first { $0.isForced != true }?.id
            ?? tracks.first?.id
    }

    /// Outer optional distinguishes no preference from an explicit Off choice.
    static func selection(kind: String, streams: [PlexStream], details: PlexMediaDetails, profile: String?, defaults: UserDefaults = .standard) -> Int?? {
        guard let key = key(details: details, profile: profile, kind: kind),
              let data = defaults.data(forKey: key),
              let preference = try? JSONDecoder().decode(Track.self, from: data) else { return nil }
        if preference.off { return .some(nil) }
        // A missing remembered language/format is not an explicit Off choice.
        guard let match = preference.matching(streams) else { return nil }
        return .some(match.id)
    }
}
