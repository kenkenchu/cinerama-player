import VLCKit
import Foundation

enum VLCKitBuildInfo {
    /// Dusk build label (e.g. `3.7.3-dusk1`); nil for a stock VideoLAN build.
    static let duskBuild: String? = frameworkInfo["DuskVLCKitBuild"] as? String

    /// Whether libvlc decodes Dolby TrueHD/MLP (to PCM, up to 7.1; for TrueHD
    /// Atmos that is the 7.1 bed).
    static let decodesTrueHD: Bool = frameworkInfo["DuskVLCKitTrueHD"] as? Bool ?? false

    private static var frameworkInfo: [String: Any] {
        Bundle(for: VLCMediaPlayer.self).infoDictionary ?? [:]
    }
}
