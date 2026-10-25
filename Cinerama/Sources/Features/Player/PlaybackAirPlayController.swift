import Foundation
import Observation


/// Observes the system media route selected for Cinerama's long-form video audio
/// session. The coordinator uses this signal to replace VLC-only/direct-play
/// sources with an AVPlayer-compatible Plex HLS stream before handing video to
/// an AirPlay receiver.
@MainActor @Observable
final class PlaybackAirPlayController {
    private(set) var isAirPlayRouteSelected = false
    private(set) var routeDisplayName: String?
    @ObservationIgnored var routeSelectionDidChange: (@MainActor (Bool) -> Void)?

    init() {}

    func refreshRoute(notify: Bool = true) {}
}
