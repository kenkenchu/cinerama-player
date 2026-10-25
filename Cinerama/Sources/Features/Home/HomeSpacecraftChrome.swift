import SwiftUI

/// Static architectural decoration. Never participates in focus, hit testing
/// or accessibility, and has no animation loop while Home is idle.
struct HomeDeckBackground: View {
    var body: some View {
        Color.cineramaBackground
            .overlay {
                Canvas { context, size in
                    // Deterministic, sparse points rather than animated particles.
                    for index in 0..<54 {
                        let x = CGFloat((index * 137 + 29) % 997) / 997 * size.width
                        let y = CGFloat((index * 211 + 71) % 991) / 991 * size.height
                        let diameter: CGFloat = index.isMultiple(of: 7) ? 2 : 1
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                            with: .color(.primary.opacity(index.isMultiple(of: 7) ? 0.22 : 0.10))
                        )
                    }

                    var grid = Path()
                    let horizon = size.height * 0.42
                    let vanishingPoint = CGPoint(x: size.width * 0.5, y: horizon)
                    for index in -4...8 {
                        grid.move(to: vanishingPoint)
                        grid.addLine(to: CGPoint(x: CGFloat(index) * size.width / 4, y: size.height))
                    }
                    for fraction: CGFloat in [0.08, 0.20, 0.37, 0.63, 1] {
                        let y = horizon + (size.height - horizon) * fraction
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(.primary.opacity(0.035)), lineWidth: 0.5)
                }
            }
            .overlay {
                RadialGradient(colors: [.primary.opacity(0.045), .clear],
                               center: .top, startRadius: 0, endRadius: 650)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct HomeDeckHeader: View {
    let featuredCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("CINERAMA / HOME")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Text("Screening deck")
                    .font(.system(.largeTitle, design: .default, weight: .light))
                    .tracking(-0.8)
            }
            Spacer(minLength: 8)
            if featuredCount > 0 {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(featuredCount, format: .number.precision(.integerLength(2)))
                        .font(.system(.title2, design: .monospaced, weight: .light))
                    Text("ON DECK")
                        .font(.system(.caption2, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(featuredCount) featured titles")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

struct HomeViewportFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06), .white.opacity(0.20)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                    .overlay {
                        HomeViewportCorners()
                            .stroke(.white.opacity(0.50), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                            .padding(10)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.22), radius: 20, y: 12)
    }
}

private struct HomeViewportCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 22
        let radius: CGFloat = 14
        for right in [false, true] {
            for bottom in [false, true] {
                let x = right ? rect.maxX : rect.minX
                let y = bottom ? rect.maxY : rect.minY
                let dx: CGFloat = right ? -1 : 1
                let dy: CGFloat = bottom ? -1 : 1
                path.move(to: CGPoint(x: x, y: y + dy * length))
                path.addLine(to: CGPoint(x: x, y: y + dy * radius))
                path.addQuadCurve(to: CGPoint(x: x + dx * radius, y: y),
                                  control: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + dx * length, y: y))
            }
        }
        return path
    }
}

struct HomeLibraryBay: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 20)
            .background {
                let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
                if reduceTransparency {
                    shape.fill(Color.cineramaSurface)
                } else {
                    shape.fill(Color.cineramaSurface.opacity(0.82))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 0.75)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
