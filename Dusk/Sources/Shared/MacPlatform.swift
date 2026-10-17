import SwiftUI

import AppKit

extension Color {
    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let duskBackground = adaptive("DuskBackground", light: 0xF5F7FA, dark: 0x090A0F)
    static let duskSurface = adaptive("DuskSurface", light: 0xFFFFFF, dark: 0x161824)
    static let duskTextPrimary = adaptive("DuskTextPrimary", light: 0x1C1C1E, dark: 0xF2F2F7)
    static let duskTextSecondary = adaptive("DuskTextSecondary", light: 0x636366, dark: 0x8E95A8)
    static let duskAccent = Color(red: 1, green: 107.0 / 255, blue: 74.0 / 255)
    static let duskPrimaryActionLabel = adaptive("DuskActionLabel", light: 0xFFFFFF, dark: 0x090A0F)
    static var duskPrimaryButtonTint: Color { .primary.opacity(0.7) }
}
