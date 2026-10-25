import SwiftUI
import AppKit

/// Cinerama's fixed metallic-blue palette, independent of macOS appearance.
/// Native controls use Dark Aqua; video and letterboxing keep true black.
extension Color {
    private static func metalBlue(_ hex: UInt32) -> Color {
        Color(nsColor: NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                               green: Double((hex >> 8) & 255) / 255,
                               blue: Double(hex & 255) / 255, alpha: 1))
    }
    static let cineramaBackground = metalBlue(0x1D2D40)
    static let cineramaSurface = metalBlue(0x2D455F)
    static let cineramaTextPrimary = metalBlue(0xF2F2F7)
    static let cineramaTextSecondary = metalBlue(0xB2C5D9)
    static let cineramaAccent = Color(red: 1, green: 107.0 / 255, blue: 74.0 / 255)
    static let cineramaPrimaryActionLabel = metalBlue(0x1D2D40)
    static var cineramaPrimaryButtonTint: Color { .primary.opacity(0.7) }
}

/// One window-level backdrop; catalog screens stay clear rather than stacking
/// opaque fills or multiple blur layers over the desktop.
struct CineramaWindowBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color.cineramaBackground
            } else {
                CineramaDesktopMaterial()
                    .glassEffect(.clear.tint(Color.cineramaBackground.opacity(0.28)), in: Rectangle())
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CineramaDesktopMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
