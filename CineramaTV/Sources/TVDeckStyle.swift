import SwiftUI

/// Keep these values aligned with MacPlatform.swift; platform rendering stays separate.
enum TVDeckPalette {
    static let background = Color(red: 29.0 / 255, green: 45.0 / 255, blue: 64.0 / 255)
    static let surface = Color(red: 45.0 / 255, green: 69.0 / 255, blue: 95.0 / 255)
    static let secondary = Color(red: 178.0 / 255, green: 197.0 / 255, blue: 217.0 / 255)
}

/// TV-owned screening-deck styling. Static decoration keeps A8 rendering bounded.
struct TVDeckBackground: View {
    var body: some View {
        LinearGradient(colors: [TVDeckPalette.surface, TVDeckPalette.background, TVDeckPalette.background],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Canvas { context, size in
                    for index in 0..<42 {
                        let x = CGFloat((index * 137 + 41) % 997) / 997 * size.width
                        let y = CGFloat((index * 83 + 17) % 499) / 499 * size.height
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                                     with: .color(.white.opacity(index.isMultiple(of: 3) ? 0.22 : 0.09)))
                    }
                    var grid = Path()
                    let horizon = size.height * 0.58
                    for index in -6...6 {
                        grid.move(to: CGPoint(x: size.width / 2 + CGFloat(index) * 38, y: horizon))
                        grid.addLine(to: CGPoint(x: size.width / 2 + CGFloat(index) * 300, y: size.height))
                    }
                    for fraction in [0.0, 0.12, 0.30, 0.57, 1.0] {
                        let y = horizon + (size.height - horizon) * fraction
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.055)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct TVDeckBay: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 28)
            .background {
                RoundedRectangle(cornerRadius: 28)
                    .fill(TVDeckPalette.surface.opacity(reduceTransparency ? 1 : 0.7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .padding(.horizontal, 36)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

struct TVDeckRule: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct TVViewportEdge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            .overlay {
                Canvas { context, size in
                    var brackets = Path()
                    for right in [false, true] {
                        for bottom in [false, true] {
                            let x: CGFloat = right ? size.width - 18 : 18
                            let y: CGFloat = bottom ? size.height - 18 : 18
                            brackets.move(to: CGPoint(x: x, y: y + (bottom ? -32 : 32)))
                            brackets.addLine(to: CGPoint(x: x, y: y))
                            brackets.addLine(to: CGPoint(x: x + (right ? -48 : 48), y: y))
                        }
                    }
                    context.stroke(brackets, with: .color(.white.opacity(0.55)), lineWidth: 2)
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Native button styles preserve tvOS focus/activation, including accessibility.
struct TVDeckActionStyle: ViewModifier {
    var prominent = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            if prominent {
                content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            } else {
                content.buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        } else if prominent {
            content.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
        }
    }
}

/// Translucency samples the title artwork on TV, rather than a Mac desktop.
struct TVDeckInformationPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 28).fill(TVDeckPalette.background)
                }
            }
            .glassEffect(reduceTransparency ? .identity : .regular.tint(TVDeckPalette.background.opacity(0.65)),
                         in: RoundedRectangle(cornerRadius: 28))
    }
}

/// Ten-foot layout values leave room for native focused cards to expand.
enum TVDeckLayout {
    static let horizontalInset: CGFloat = 80
    static let verticalInset: CGFloat = 60
    static let sectionSpacing: CGFloat = 48
    static let cardSpacing: CGFloat = 40
    static let heroHeight: CGFloat = 660
}

struct TVDeckSectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2.bold())
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(TVDeckPalette.secondary)
                }
            }
            TVDeckRule()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct TVDeckPageInsets: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, TVDeckLayout.horizontalInset)
            .padding(.vertical, TVDeckLayout.verticalInset)
    }
}
