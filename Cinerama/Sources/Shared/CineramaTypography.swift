import SwiftUI

/// Semantic typography roles. macOS resolves each supplied system text style.
enum CineramaFont {
    static func heroTitle(style: Font) -> Font { style }
    static func heroTitleRounded(style: Font) -> Font { style }
    static func heroSubtitle(style: Font) -> Font { style }
    static func pageTitle(style: Font) -> Font { style }
    static func pageTitleRounded(style: Font) -> Font { style }
    static func pageSubtitle(style: Font) -> Font { style }
    static func sectionHeader(style: Font) -> Font { style }
    static func groupHeader(style: Font) -> Font { style }
    static func rowTitle(style: Font) -> Font { style }
    static func rowValue(style: Font) -> Font { style }
    static func cardTitle(style: Font) -> Font { style }
    static func cardSubtitle(style: Font) -> Font { style }
    static func body(style: Font) -> Font { style }
    static func metadata(style: Font) -> Font { style }
    static func caption(style: Font) -> Font { style }
    static func buttonLabel(style: Font) -> Font { style }
    static func badge(style: Font) -> Font { style }
    static func glyphSmall(style: Font) -> Font { style }
    static func glyphMedium(style: Font) -> Font { style }
    static func glyphLarge(style: Font) -> Font { style }
    static func playerTitle(style: Font) -> Font { style }
    static func playerTitleCompact(style: Font) -> Font { style }
    static func playerOverlayTitle(style: Font) -> Font { style }
}
