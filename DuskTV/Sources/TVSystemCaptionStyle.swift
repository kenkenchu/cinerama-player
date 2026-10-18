import AVFoundation
import CoreMedia
import CoreText
import MediaAccessibility
import UIKit

/// Translate only system preferences that explicitly override authored content.
/// No Dusk caption settings or persisted appearance values are introduced.
enum TVSystemCaptionStyle {
    static func rules() -> [AVTextStyleRule]? {
        let domain = MACaptionAppearanceDomain.user
        var attributes: [String: Any] = [:]
        var behavior = MACaptionAppearanceBehavior.useContentIfAvailable
        let foreground = MACaptionAppearanceCopyForegroundColor(domain, &behavior).takeRetainedValue()
        let foregroundOverrides = behavior == .useValue
        let foregroundOpacity = MACaptionAppearanceGetForegroundOpacity(domain, &behavior)
        if foregroundOverrides || behavior == .useValue {
            attributes[kCMTextMarkupAttribute_ForegroundColorARGB as String] = argb(foreground, opacity: foregroundOpacity)
        }
        let background = MACaptionAppearanceCopyBackgroundColor(domain, &behavior).takeRetainedValue()
        let backgroundOverrides = behavior == .useValue
        let backgroundOpacity = MACaptionAppearanceGetBackgroundOpacity(domain, &behavior)
        if backgroundOverrides || behavior == .useValue {
            attributes[kCMTextMarkupAttribute_CharacterBackgroundColorARGB as String] = argb(background, opacity: backgroundOpacity)
        }
        let window = MACaptionAppearanceCopyWindowColor(domain, &behavior).takeRetainedValue()
        let windowOverrides = behavior == .useValue
        let windowOpacity = MACaptionAppearanceGetWindowOpacity(domain, &behavior)
        if windowOverrides || behavior == .useValue {
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = argb(window, opacity: windowOpacity)
        }
        let descriptor = MACaptionAppearanceCopyFontDescriptorForStyle(domain, &behavior, .default).takeRetainedValue()
        if behavior == .useValue, let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String {
            attributes[kCMTextMarkupAttribute_FontFamilyName as String] = family
            let traits = CTFontGetSymbolicTraits(CTFontCreateWithFontDescriptor(descriptor, 0, nil))
            attributes[kCMTextMarkupAttribute_BoldStyle as String] = traits.contains(.traitBold)
            attributes[kCMTextMarkupAttribute_ItalicStyle as String] = traits.contains(.traitItalic)
        }
        let scale = MACaptionAppearanceGetRelativeCharacterSize(domain, &behavior)
        if behavior == .useValue, scale.isFinite, scale > 0 {
            attributes[kCMTextMarkupAttribute_RelativeFontSize as String] = scale * 100
        }
        let edge = MACaptionAppearanceGetTextEdgeStyle(domain, &behavior)
        if behavior == .useValue {
            let value: CFString
            switch edge {
            case .raised: value = kCMTextMarkupCharacterEdgeStyle_Raised
            case .depressed: value = kCMTextMarkupCharacterEdgeStyle_Depressed
            case .uniform: value = kCMTextMarkupCharacterEdgeStyle_Uniform
            case .dropShadow: value = kCMTextMarkupCharacterEdgeStyle_DropShadow
            default: value = kCMTextMarkupCharacterEdgeStyle_None
            }
            attributes[kCMTextMarkupAttribute_CharacterEdgeStyle as String] = value as String
        }
        guard !attributes.isEmpty, let rule = AVTextStyleRule(textMarkupAttributes: attributes) else { return nil }
        return [rule]
    }

    private static func argb(_ color: CGColor, opacity: CGFloat) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        UIColor(cgColor: color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [opacity, red, green, blue]
    }
}
