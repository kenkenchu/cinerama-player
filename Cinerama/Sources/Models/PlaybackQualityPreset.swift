import Foundation

enum PlaybackQualityPreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case p1080_20Mbps
    case p1080_12Mbps
    case p1080_10Mbps
    case p1080_8Mbps
    case p720_4Mbps
    case p720_3Mbps
    case p720_2Mbps
    case p480_1_5Mbps
    case p320_720Kbps
    case p240_320Kbps

    var id: String { rawValue }

    var isOriginal: Bool {
        self == .original
    }

    var displayName: String {
        switch self {
        case .original: "Original"
        case .p1080_20Mbps: "1080p • 20 Mbps"
        case .p1080_12Mbps: "1080p • 12 Mbps"
        case .p1080_10Mbps: "1080p • 10 Mbps"
        case .p1080_8Mbps: "1080p • 8 Mbps"
        case .p720_4Mbps: "720p • 4 Mbps"
        case .p720_3Mbps: "720p • 3 Mbps"
        case .p720_2Mbps: "720p • 2 Mbps"
        case .p480_1_5Mbps: "480p • 1.5 Mbps"
        case .p320_720Kbps: "320p • 720 kbps"
        case .p240_320Kbps: "240p • 320 kbps"
        }
    }

    var detailTitle: String? {
        switch self {
        case .original:
            "Direct Play"
        default:
            "Transcoded"
        }
    }

    var videoHeight: Int? {
        switch self {
        case .original: nil
        case .p1080_20Mbps, .p1080_12Mbps, .p1080_10Mbps, .p1080_8Mbps:
            1080
        case .p720_4Mbps, .p720_3Mbps, .p720_2Mbps:
            720
        case .p480_1_5Mbps:
            480
        case .p320_720Kbps:
            320
        case .p240_320Kbps:
            240
        }
    }

    var videoBitrateKbps: Int? {
        switch self {
        case .original: nil
        case .p1080_20Mbps: 20_000
        case .p1080_12Mbps: 12_000
        case .p1080_10Mbps: 10_000
        case .p1080_8Mbps: 8_000
        case .p720_4Mbps: 4_000
        case .p720_3Mbps: 3_000
        case .p720_2Mbps: 2_000
        case .p480_1_5Mbps: 1_500
        case .p320_720Kbps: 720
        case .p240_320Kbps: 320
        }
    }

    var videoResolution: String? {
        switch self {
        case .original: nil
        case .p1080_20Mbps, .p1080_12Mbps, .p1080_10Mbps, .p1080_8Mbps:
            "1920x1080"
        case .p720_4Mbps, .p720_3Mbps, .p720_2Mbps:
            "1280x720"
        case .p480_1_5Mbps:
            "720x480"
        case .p320_720Kbps:
            "576x320"
        case .p240_320Kbps:
            "420x240"
        }
    }

    var videoQuality: Int? {
        switch self {
        case .original: nil
        case .p1080_20Mbps: 100
        case .p1080_12Mbps: 90
        case .p1080_10Mbps: 75
        case .p1080_8Mbps: 60
        case .p720_4Mbps: 100
        case .p720_3Mbps: 75
        case .p720_2Mbps: 60
        case .p480_1_5Mbps: 60
        case .p320_720Kbps: 40
        case .p240_320Kbps: 30
        }
    }

    static let displayOrder: [PlaybackQualityPreset] = [
        .original,
        .p1080_20Mbps,
        .p1080_12Mbps,
        .p1080_10Mbps,
        .p1080_8Mbps,
        .p720_4Mbps,
        .p720_3Mbps,
        .p720_2Mbps,
        .p480_1_5Mbps,
        .p320_720Kbps,
        .p240_320Kbps,
    ]

    static func displayOrder(forOriginalMedia media: PlexMedia) -> [PlaybackQualityPreset] {
        let videoStreams = media.parts.flatMap { $0.streams }.filter { $0.streamType == .video }
        let originalHeight = media.height
            ?? videoStreams.compactMap(\.height).first
            ?? height(fromVideoResolution: media.videoResolution)
        let originalBitrate = media.bitrate ?? videoStreams.compactMap(\.bitrate).first

        return displayOrder.filter { preset in
            preset.isOriginal || preset.isBelowOriginal(height: originalHeight, bitrate: originalBitrate)
        }
    }

    private func isBelowOriginal(height originalHeight: Int?, bitrate originalBitrate: Int?) -> Bool {
        guard let presetHeight = videoHeight else { return true }

        if let originalHeight {
            if presetHeight < originalHeight {
                return true
            }

            if presetHeight > originalHeight {
                return false
            }

            guard let presetBitrate = videoBitrateKbps,
                  let originalBitrate else {
                return false
            }

            return presetBitrate < originalBitrate
        }

        guard let presetBitrate = videoBitrateKbps,
              let originalBitrate else {
            return true
        }

        return presetBitrate < originalBitrate
    }

    private static func height(fromVideoResolution videoResolution: String?) -> Int? {
        guard let videoResolution else { return nil }

        let normalized = videoResolution.lowercased()
        if normalized.contains("4k") || normalized.contains("uhd") {
            return 2160
        }

        if normalized.contains("1080") { return 1080 }
        if normalized.contains("720") { return 720 }
        if normalized.contains("576") { return 576 }
        if normalized.contains("480") || normalized.contains("sd") { return 480 }
        if normalized.contains("320") { return 320 }
        if normalized.contains("240") { return 240 }

        return nil
    }
}
