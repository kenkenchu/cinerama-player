import VLCKit
import Foundation

enum VLCKitBuildInfo {
    /// Cinerama build label (e.g. `3.7.3-cinerama1`); nil for a stock VideoLAN build.
    static let cineramaBuild: String? = frameworkInfo["CineramaVLCKitBuild"] as? String

    /// Whether libvlc decodes Dolby TrueHD/MLP (to PCM, up to 7.1; for TrueHD
    /// Atmos that is the 7.1 bed).
    static let decodesTrueHD: Bool = frameworkInfo["CineramaVLCKitTrueHD"] as? Bool ?? false

    private static var frameworkInfo: [String: Any] {
        Bundle(for: VLCMediaPlayer.self).infoDictionary ?? [:]
    }
}
