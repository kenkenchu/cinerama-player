import SwiftUI
import AppKit

/// Cinerama's fixed graphite palette, independent of macOS appearance.
/// Native controls use Dark Aqua; video and letterboxing keep true black.
extension Color {
    private static func graphite(_ hex: UInt32) -> Color {
        Color(nsColor: NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                               green: Double((hex >> 8) & 255) / 255,
                               blue: Double(hex & 255) / 255, alpha: 1))
    }
    static let cineramaBackground = graphite(0x1C2029)
    static let cineramaSurface = graphite(0x292F3B)
    static let cineramaTextPrimary = graphite(0xF2F2F7)
    static let cineramaTextSecondary = graphite(0xADB5C6)
    static let cineramaAccent = Color(red: 1, green: 107.0 / 255, blue: 74.0 / 255)
    static let cineramaPrimaryActionLabel = graphite(0x1C2029)
    static var cineramaPrimaryButtonTint: Color { .primary.opacity(0.7) }
}
