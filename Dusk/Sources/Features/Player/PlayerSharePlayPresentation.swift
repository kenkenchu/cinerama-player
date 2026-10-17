import GroupActivities
import SwiftUI


/// Present from the player cover while it is open, and from the app root for
/// incoming invitations that need sign-in. The root cannot alert over a cover.
private struct PlayerSharePlayPresentation: ViewModifier {
    @Environment(PlaybackCoordinator.self) private var playback
    let isPlayer: Bool

    private var isPresentationHost: Bool {
        playback.showPlayer == isPlayer
    }

    func body(content: Content) -> some View {
        content
            .alert(
                "SharePlay",
                isPresented: Binding(
                    get: { isPresentationHost && playback.sharePlayError != nil },
                    set: { presented in
                        if !presented, isPresentationHost {
                            playback.dismissSharePlayError()
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    playback.dismissSharePlayError()
                }
            } message: {
                Text(playback.sharePlayError ?? "SharePlay is unavailable.")
            }
    }
}

extension View {
    func playerSharePlayPresentation(isPlayer: Bool) -> some View {
        modifier(PlayerSharePlayPresentation(isPlayer: isPlayer))
    }
}
