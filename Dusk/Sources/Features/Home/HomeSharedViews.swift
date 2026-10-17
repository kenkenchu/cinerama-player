import SwiftUI

struct HomeItemContextMenu: View {
    let item: PlexItem
    let detailsLabel: String
    let onMarkWatched: () -> Void
    let onMarkUnwatched: () -> Void
    let onSelectRoute: (AppNavigationRoute) -> Void
    var onRemoveFromContinueWatching: (() -> Void)?

    var body: some View {
        if item.canMarkWatchedFromContextMenu {
            Button("Mark Watched", systemImage: "eye", action: onMarkWatched)
        }

        if item.canMarkUnwatchedFromContextMenu {
            Button("Mark Unwatched", systemImage: "eye.slash", action: onMarkUnwatched)
        }

        if let onRemoveFromContinueWatching {
            Button("Remove from Continue Watching", systemImage: "minus.circle", action: onRemoveFromContinueWatching)
        }

        Button(detailsLabel, systemImage: "info.circle") {
            onSelectRoute(AppNavigationRoute.destination(for: item))
        }

        if let seasonRoute = item.contextMenuSeasonRoute {
            Button("Go to Season", systemImage: "rectangle.stack") {
                onSelectRoute(seasonRoute)
            }
        }

        if let showRoute = item.contextMenuShowRoute {
            Button("Go to Show", systemImage: "tv.fill") {
                onSelectRoute(showRoute)
            }
        }
    }
}

struct HomeHeroActionButtonLabel: View {
    let title: String
    let systemImage: String
    var fillsWidth: Bool = false


    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(heroButtonFont)

            Text(title)
                .font(heroButtonFont)
                .lineLimit(1)
        }
        .frame(minHeight: heroButtonMinHeight)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .contentShape(Capsule())
        .foregroundStyle(labelColor)
    }

    private var labelColor: Color {
        .duskPrimaryActionLabel
    }

    private var heroButtonFont: Font {
        .headline.weight(.semibold)
    }

    private var heroButtonMinHeight: CGFloat {
        32
    }
}

/// A neutral progress tint over the native button, with no separate hit target.
struct HomeHeroResumeProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.primary.opacity(0.14))
                .frame(width: geometry.size.width * min(1, max(0, progress)))
                .frame(maxHeight: .infinity)
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The pager pills on screen when the hero has more items than
/// `maxVisible`, in the manner of `UIPageControl`: a fixed number of slots that
/// slides to keep the current item centred, with the outermost pills shrunk on
/// a side where more items lie beyond. The pager's width is therefore bounded
/// however long Continue Watching grows.
struct HomeHeroPagerWindow {
    let range: Range<Int>
    private let count: Int

    init(count: Int, currentIndex: Int, maxVisible: Int) {
        let visible = min(max(count, 0), max(maxVisible, 1))
        let start = min(max(currentIndex - visible / 2, 0), max(count, 0) - visible)
        range = start ..< start + visible
        self.count = count
    }

    func scale(for index: Int) -> CGFloat {
        let fromLeadingEdge = range.lowerBound > 0 ? index - range.lowerBound : .max
        let fromTrailingEdge = range.upperBound < count ? range.upperBound - 1 - index : .max

        switch min(fromLeadingEdge, fromTrailingEdge) {
        case 0: return 0.5
        case 1: return 0.75
        default: return 1
        }
    }
}

struct HomeHeroPagerPill: View {
    let isActive: Bool
    let progress: Double

    var body: some View {
        let pillWidth: CGFloat = isActive ? 28 : 10
        let pillHeight: CGFloat = 10
        let fillInset: CGFloat = 1
        let clampedProgress = min(max(progress, 0), 1)

        ZStack(alignment: .leading) {
            Capsule()
                .fill(isActive ? Color.primary.opacity(0.24) : Color.primary.opacity(0.28))

            if isActive {
                Capsule()
                    .fill(Color.primary)
                    .frame(
                        width: max((pillWidth - (fillInset * 2)) * clampedProgress, 0),
                        height: pillHeight - (fillInset * 2)
                    )
                    .padding(fillInset)
                    .clipShape(Capsule())
            }
        }
        .frame(width: pillWidth, height: pillHeight)
        .clipShape(Capsule())
        .overlay {
            if isActive {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func homeHeroNativeButtonStyle() -> some View {
        self
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
    }
}
