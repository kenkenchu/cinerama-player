import SwiftUI

extension View {
    @ViewBuilder
    func duskNavigationTitle(_ title: String) -> some View {
        self.navigationTitle(title)
    }

    @ViewBuilder
    func duskScrollContentBackgroundHidden() -> some View {
        self.scrollContentBackground(.hidden)
    }

    @ViewBuilder
    func duskListRowSeparatorHidden() -> some View {
        self.listRowSeparator(.hidden)
    }

}

enum DuskPosterMetrics {
    static var carouselSectionSpacing: CGFloat {
        12
    }

    static var carouselHeaderSpacing: CGFloat {
        12
    }

    static var carouselItemSpacing: CGFloat {
        12
    }

    static var carouselHorizontalPadding: CGFloat {
        16
    }

    static var libraryPageHorizontalPadding: CGFloat {
        20
    }

    static var carouselBottomPadding: CGFloat {
        2
    }

    static var pageSectionSpacing: CGFloat {
        18
    }

    static var pageBottomPadding: CGFloat {
        24
    }

    static var cardSpacing: CGFloat {
        6
    }

    static var cardTextSpacing: CGFloat {
        0
    }

    static var gridHorizontalPadding: CGFloat {
        12
    }

    static var detailHorizontalPadding: CGFloat {
        20
    }

    static var gridSpacing: CGFloat {
        12
    }

    static var gridRowSpacing: CGFloat {
        18
    }

    static var gridPreferredWidth: CGFloat {
        104
    }

    static var detailGridSpacing: CGFloat {
        14
    }

    static var detailGridRowSpacing: CGFloat {
        18
    }

    static var detailGridPreferredWidth: CGFloat {
        120
    }

    static var carouselPosterWidth: CGFloat {
        130
    }

    static var videoGridPreferredWidth: CGFloat {
        168
    }

    /// 16:9 video-card width for carousels, the landscape counterpart of
    /// `carouselPosterWidth`.
    static var videoCarouselWidth: CGFloat {
        200
    }

    static var continueWatchingWidth: CGFloat {
        280
    }

    static var heroPosterWidth: CGFloat {
        180
    }

    static var titleFont: Font { DuskFont.cardTitle(style: .caption) }

    static var subtitleFont: Font { DuskFont.cardSubtitle(style: .caption2) }

    static var posterProgressBarHeight: CGFloat {
        5
    }
}

struct DetailHeroBackdrop: View {
    @Environment(PlexService.self) private var plexService

    let imageURL: URL?
    let height: CGFloat
    var imageAlignment: Alignment = .center
    var keepsPreviousImageWhileLoading = false


    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.duskSurface

                if keepsPreviousImageWhileLoading {
                    retainedBackdropImage(size: geometry.size)
                } else {
                    asyncBackdropImage(size: geometry.size)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: imageAlignment
            )
            .clipped()
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .task(id: imageURL) {
            await loadRetainedImageIfNeeded()
        }
    }

    @ViewBuilder
    private func asyncBackdropImage(size: CGSize) -> some View {
        if let imageURL {
            DuskAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    backdropImage(image, size: size)
                default:
                    Color.clear
                }
            }
        }
    }

    @ViewBuilder
    private func retainedBackdropImage(size: CGSize) -> some View {
        asyncBackdropImage(size: size)
    }

    private func backdropImage(_ image: Image, size: CGSize) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: imageAlignment)
            .frame(
                width: size.width,
                height: size.height,
                alignment: imageAlignment
            )
            .clipped()
    }

    @MainActor
    private func loadRetainedImageIfNeeded() async {
        guard keepsPreviousImageWhileLoading else { return }

    }
}

enum DuskHeroOverlayStyle {
    case standard
    /// Lighter scrim that lets more of the backdrop read through. Used by the
    /// movie/show/season/episode detail heroes, where the artwork should lead
    /// and the title block sits in the lower third over a still-solid base.
    case soft
    case cinematic


    /// Top-to-bottom darkening applied across the whole hero. `.soft` keeps the
    /// upper two thirds close to clear and only ramps up behind the title block.
    var verticalDarkeningStops: [Gradient.Stop] {
        switch self {
        case .standard:
            return [
                .init(color: Color.black.opacity(0.18), location: 0),
                .init(color: Color.black.opacity(0.56), location: 0.62),
                .init(color: Color.black.opacity(0.86), location: 1),
            ]
        case .cinematic:
            // A short top band keeps the status bar and toolbar legible; the
            // middle stays nearly clear and the darkening waits for the title block.
            return [
                .init(color: Color.black.opacity(0.30), location: 0),
                .init(color: Color.black.opacity(0.08), location: 0.14),
                .init(color: Color.black.opacity(0.12), location: 0.50),
                .init(color: Color.black.opacity(0.42), location: 0.78),
                .init(color: Color.black.opacity(0.72), location: 1),
            ]
        case .soft:
            return [
                .init(color: Color.black.opacity(0.14), location: 0),
                .init(color: Color.black.opacity(0.14), location: 0.34),
                .init(color: Color.black.opacity(0.24), location: 0.62),
                .init(color: Color.black.opacity(0.48), location: 0.82),
                .init(color: Color.black.opacity(0.70), location: 1),
            ]
        }
    }

    /// Bottom fade into `Color.duskBackground` that blends the hero into the
    /// page and backs the title block. Both styles still reach full opacity
    /// before the hero edge so the join to the page stays seamless; `.soft`
    /// simply holds the fade off until the lower third.
    var bottomBackgroundFadeStops: [Gradient.Stop] {
        switch self {
        case .cinematic:
            return [
                .init(color: Color.duskBackground.opacity(0), location: 0),
                .init(color: Color.duskBackground.opacity(0), location: 0.58),
                .init(color: Color.duskBackground.opacity(0.10), location: 0.70),
                .init(color: Color.duskBackground.opacity(0.36), location: 0.81),
                .init(color: Color.duskBackground.opacity(0.72), location: 0.90),
                .init(color: Color.duskBackground, location: 0.96),
                .init(color: Color.duskBackground, location: 1),
            ]
        case .standard:
            return [
                .init(color: Color.duskBackground.opacity(0), location: 0),
                .init(color: Color.duskBackground.opacity(0), location: 0.20),
                .init(color: Color.duskBackground.opacity(0.08), location: 0.38),
                .init(color: Color.duskBackground.opacity(0.28), location: 0.54),
                .init(color: Color.duskBackground.opacity(0.60), location: 0.68),
                .init(color: Color.duskBackground.opacity(0.90), location: 0.80),
                .init(color: Color.duskBackground, location: 0.88),
                .init(color: Color.duskBackground, location: 1),
            ]
        case .soft:
            return [
                .init(color: Color.duskBackground.opacity(0), location: 0),
                .init(color: Color.duskBackground.opacity(0), location: 0.40),
                .init(color: Color.duskBackground.opacity(0.06), location: 0.52),
                .init(color: Color.duskBackground.opacity(0.22), location: 0.64),
                .init(color: Color.duskBackground.opacity(0.48), location: 0.74),
                .init(color: Color.duskBackground.opacity(0.80), location: 0.84),
                .init(color: Color.duskBackground, location: 0.92),
                .init(color: Color.duskBackground, location: 1),
            ]
        }
    }
}

struct DuskHeroBackdropOverlay: View {
    var style: DuskHeroOverlayStyle = .standard

    private let bottomBackgroundHeight: CGFloat = 24

    var body: some View {
        ZStack {
            LinearGradient(
                stops: style.verticalDarkeningStops,
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.86), location: 0),
                    .init(color: Color.black.opacity(0.50), location: 0.34),
                    .init(color: Color.black.opacity(0.12), location: 0.68),
                    .init(color: Color.black.opacity(0), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                stops: style.bottomBackgroundFadeStops,
                startPoint: .top,
                endPoint: .bottom
            )

            Color.duskBackground
                .frame(maxWidth: .infinity)
                .frame(height: bottomBackgroundHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }
}
