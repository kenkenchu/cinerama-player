import SwiftUI

// MARK: - Detail Hero Section

@MainActor
func usesFullWidthDetailActionButtons(for sizeClass: UserInterfaceSizeClass?) -> Bool {
    false
}

var detailHeroActionSpacing: CGFloat {
    12
}

var detailHeroActionLabelMinHeight: CGFloat {
    34
}


@MainActor
func detailHeroContentAlignment(for sizeClass: UserInterfaceSizeClass?) -> HorizontalAlignment {
    usesFullWidthDetailActionButtons(for: sizeClass) ? .center : .leading
}

/// Text alignment counterpart to `detailHeroContentAlignment(for:)`.
@MainActor
func detailHeroTextAlignment(for sizeClass: UserInterfaceSizeClass?) -> TextAlignment {
    usesFullWidthDetailActionButtons(for: sizeClass) ? .center : .leading
}

@MainActor
func detailShowsSynopsisBelowHero(for sizeClass: UserInterfaceSizeClass?) -> Bool {
    sizeClass != .regular
}

struct OfflineMetadataBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(CineramaFont.glyphSmall(style: .caption.weight(.semibold)))
                .foregroundStyle(Color.cineramaTextSecondary)

            Text(message)
                .font(CineramaFont.caption(style: .caption.weight(.medium)))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.cineramaSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct DetailHeroShowTitleLink: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let title: String
    let logoURL: URL?
    let showRoute: AppNavigationRoute?

    // This is the show logo in its subordinate *supertitle* role (above a
    // season/episode text title), so it stays intentionally smaller than the
    // hero's main title artwork (`DetailHeroSection.titleArtworkHeight`).
    private var logoHeight: CGFloat {
        sizeClass == .regular ? 68 : 60
    }

    var body: some View {
        if let showRoute {
            NavigationLink(value: showRoute) {
                content
            }
            .buttonStyle(.plain)

        } else {
            content
        }
    }

    private var contentAlignment: Alignment {
        sizeClass == .regular ? .leading : .center
    }

    @ViewBuilder
    private var content: some View {
        if let logoURL {
            CineramaAsyncImage(url: logoURL) { phase in
                switch phase {
                case let .success(image):
                    let art = image
                        .resizable()
                        .scaledToFit()
                    if sizeClass == .regular {
                        art.frame(width: detailHeroRegularPrimaryWidth, alignment: contentAlignment)
                    } else {
                        art
                            .frame(maxHeight: logoHeight)
                            .frame(maxWidth: .infinity, alignment: contentAlignment)
                    }
                case .empty:
                    Color.clear
                        .frame(height: logoHeight)
                case .failure:
                    alignedTitleText
                }
            }
        } else {
            alignedTitleText
        }
    }

    private var alignedTitleText: some View {
        titleText
            .frame(maxWidth: .infinity, alignment: contentAlignment)
    }

    private var titleText: some View {
        Text(title)
            .font(CineramaFont.metadata(style: .subheadline.weight(.medium)))
            .foregroundStyle(Color.primary.opacity(0.78))
    }
}

private extension VerticalAlignment {
    enum HeroDescriptionTop: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.top]
        }
    }

    static let heroDescriptionTop = VerticalAlignment(HeroDescriptionTop.self)
}

struct DetailHeroSection<Supertitle: View, Subtitle: View, Actions: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    let backdropURL: URL?
    let titleArtworkURL: URL?
    let title: String
    var descriptionText: String? = nil
    let topInset: CGFloat
    let containerWidth: CGFloat
    var backgroundLeadingInset: CGFloat = 0
    var heroBaseHeight: CGFloat = 380
    var keepsPreviousBackdropWhileLoading = false
    var titleLineLimit: Int = 2
    /// Optional small view shown directly under the title (e.g. an episode's
    /// season·episode marker). Kept as `AnyView` so callers can opt in without
    /// adding another generic parameter to every hero.
    var titleAccessory: AnyView? = nil
    @ViewBuilder var supertitle: Supertitle
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var actions: Actions

    init(
        backdropURL: URL?,
        titleArtworkURL: URL? = nil,
        title: String,
        descriptionText: String? = nil,
        topInset: CGFloat,
        containerWidth: CGFloat,
        backgroundLeadingInset: CGFloat = 0,
        heroBaseHeight: CGFloat = 380,
        keepsPreviousBackdropWhileLoading: Bool = false,
        titleLineLimit: Int = 2,
        titleAccessory: AnyView? = nil,
        @ViewBuilder supertitle: () -> Supertitle,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder actions: () -> Actions
    ) {
        self.backdropURL = backdropURL
        self.titleArtworkURL = titleArtworkURL
        self.title = title
        self.descriptionText = descriptionText
        self.topInset = topInset
        self.containerWidth = containerWidth
        self.backgroundLeadingInset = backgroundLeadingInset
        self.heroBaseHeight = heroBaseHeight
        self.keepsPreviousBackdropWhileLoading = keepsPreviousBackdropWhileLoading
        self.titleLineLimit = titleLineLimit
        self.titleAccessory = titleAccessory
        self.supertitle = supertitle()
        self.subtitle = subtitle()
        self.actions = actions()
    }

    private var heroHeight: CGFloat { heroBaseHeight + topInset }

    var body: some View {
        let horizontalPadding: CGFloat = {
            20
        }()
        let contentTopPadding: CGFloat = {
            topInset + 64
        }()
        let contentBottomPadding: CGFloat = {
            // Sit the title block lower so it reads over the background fade
            // rather than the busier middle of the artwork — easier to read,
            // especially the dark text in Light mode.
            14
        }()
        let titleArtworkHeight: CGFloat = {
            108
        }()

        ZStack(alignment: .bottomLeading) {
            ZStack {
                DetailHeroBackdrop(
                    imageURL: backdropURL,
                    height: heroHeight,
                    keepsPreviousImageWhileLoading: keepsPreviousBackdropWhileLoading
                )

                CineramaHeroBackdropOverlay(style: .soft)
            }
            .frame(width: containerWidth, height: heroHeight, alignment: .leading)

            .offset(x: -backgroundLeadingInset)
            .allowsHitTesting(false)

            heroContent(titleArtworkHeight: titleArtworkHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, contentBottomPadding)
                .padding(.top, contentTopPadding)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func heroContent(titleArtworkHeight: CGFloat) -> some View {
        if sizeClass == .regular {
            twoColumnHeroContent(titleArtworkHeight: titleArtworkHeight)
        } else {
            centeredHeroContent(titleArtworkHeight: titleArtworkHeight)
        }
    }

    @ViewBuilder
    private func centeredHeroContent(titleArtworkHeight: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 16) {
            VStack(alignment: .center, spacing: 8) {
                supertitle
                titleView(height: titleArtworkHeight, alignment: .center)
                if let titleAccessory { titleAccessory }
                subtitle
            }

            actions
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func twoColumnHeroContent(titleArtworkHeight: CGFloat) -> some View {
        let columnWidth = detailHeroRegularPrimaryWidth

        if titleArtworkURL != nil {
            // Show / Movie: the clear-logo is the title and leads the left column;
            // the synopsis sits on the right, level with the metadata under it.
            VStack(alignment: .leading, spacing: 18) {
                titleView(height: titleArtworkHeight, alignment: .leading, width: columnWidth)

                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 16) {
                        subtitle
                        actions
                    }
                    .frame(width: columnWidth, alignment: .leading)

                    descriptionColumn
                }
            }
        } else {
            // Season / Episode: the show logo leads; the title + marker head the
            // right column, and the synopsis below them lines up with the top of
            // the Play button so it doesn't drop too low.
            VStack(alignment: .leading, spacing: 18) {
                supertitle

                HStack(alignment: .heroDescriptionTop, spacing: 36) {
                    VStack(alignment: .leading, spacing: 16) {
                        subtitle
                        actions
                            .alignmentGuide(.heroDescriptionTop) { $0[.top] }
                    }
                    .frame(width: columnWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        titleView(height: titleArtworkHeight, alignment: .leading)
                        if let titleAccessory { titleAccessory }
                        descriptionColumn
                            .alignmentGuide(.heroDescriptionTop) { $0[.top] }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var descriptionColumn: some View {
        if let descriptionText, !descriptionText.isEmpty {
            ExpandableSummaryText(
                text: descriptionText,
                collapsedLineLimit: 8,
                allowsExpansion: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func titleView(height: CGFloat, alignment: Alignment, width: CGFloat? = nil) -> some View {
        if let titleArtworkURL {
            CineramaAsyncImage(url: titleArtworkURL) { phase in
                switch phase {
                case let .success(image):
                    let art = image
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
                    if let width {
                        art.frame(width: width, alignment: alignment)
                    } else {
                        art.frame(maxWidth: .infinity, maxHeight: height, alignment: alignment)
                    }
                case .empty:
                    if let width {
                        Color.clear.frame(width: width, height: height)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: alignment)
                    }
                case .failure:
                    titleFallback(alignment: alignment)
                }
            }
        } else {
            titleFallback(alignment: alignment)
        }
    }

    private func titleFallback(alignment: Alignment) -> some View {
        Text(title)
            .font(CineramaFont.heroTitle(style: .title2.bold()))
            // Soft near-black/near-white instead of pure `Color.primary` so the
            // title reads as a gentler grey, not harsh black, in Light mode.
            .foregroundStyle(Color.cineramaTextPrimary)
            .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .lineLimit(titleLineLimit)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: alignment)
            .layoutPriority(1)
    }
}

extension DetailHeroSection where Supertitle == EmptyView {
    init(
        backdropURL: URL?,
        titleArtworkURL: URL? = nil,
        title: String,
        descriptionText: String? = nil,
        topInset: CGFloat,
        containerWidth: CGFloat,
        backgroundLeadingInset: CGFloat = 0,
        heroBaseHeight: CGFloat = 380,
        keepsPreviousBackdropWhileLoading: Bool = false,
        titleLineLimit: Int = 2,
        titleAccessory: AnyView? = nil,
        @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder actions: () -> Actions
    ) {
        self.backdropURL = backdropURL
        self.titleArtworkURL = titleArtworkURL
        self.title = title
        self.descriptionText = descriptionText
        self.topInset = topInset
        self.containerWidth = containerWidth
        self.backgroundLeadingInset = backgroundLeadingInset
        self.heroBaseHeight = heroBaseHeight
        self.keepsPreviousBackdropWhileLoading = keepsPreviousBackdropWhileLoading
        self.titleLineLimit = titleLineLimit
        self.titleAccessory = titleAccessory
        self.supertitle = EmptyView()
        self.subtitle = subtitle()
        self.actions = actions()
    }
}

struct PlayVersionContextMenu: View {
    let versions: [PlexMedia]
    let onSelectVersion: (PlexMedia) -> Void

    var body: some View {
        if !playableVersions.isEmpty {
            Menu {
                ForEach(playableVersions) { version in
                    Button {
                        onSelectVersion(version)
                    } label: {
                        Text(MediaTextFormatter.playbackVersionMenuLabel(version))
                    }
                }
            } label: {
                Label("Play Version", systemImage: "play.square")
            }
        }
    }

    private var playableVersions: [PlexMedia] {
        versions.filter { !$0.parts.isEmpty }
    }
}

extension View {
    func detailSubtitleSearchPresentation(
        isPresented: Binding<Bool>,
        viewModel: @escaping () -> SubtitleSearchViewModel
    ) -> some View {
        sheet(isPresented: isPresented) {
            SubtitleSearchView(viewModel: viewModel()) { isPresented.wrappedValue = false }
        }
    }
}

struct DetailHeroSecondaryIconLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(CineramaFont.buttonLabel(style: .subheadline.weight(.semibold)))
            .frame(minWidth: iconMinWidth, minHeight: iconMinHeight)
            .contentShape(Capsule())
    }

    private var iconMinWidth: CGFloat {
        24
    }

    private var iconMinHeight: CGFloat {
        32
    }
}

struct DetailHeroPrimaryActionButtonLabel: View {
    let title: String
    let systemImage: String
    var fillsWidth: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(CineramaFont.buttonLabel(style: .headline.weight(.semibold)))

            Text(title)
                .font(CineramaFont.buttonLabel(style: .headline))
                .lineLimit(1)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: detailHeroActionLabelMinHeight)
        .foregroundStyle(Color.cineramaPrimaryActionLabel)
        .contentShape(Capsule())
    }
}

struct DetailHeroStatusActionLabel: View {
    let title: String
    let systemImage: String
    var fillsWidth: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(CineramaFont.buttonLabel(style: .headline.weight(.semibold)))

            Text(title)
                .font(CineramaFont.buttonLabel(style: .headline))
                .lineLimit(1)
        }
        .foregroundStyle(Color.cineramaTextPrimary)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: detailHeroActionLabelMinHeight)
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(Color.cineramaSurface.opacity(0.86), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.cineramaTextSecondary.opacity(0.18), lineWidth: 1)
        }
    }
}

extension View {
    @ViewBuilder
    func detailHeroNativePrimaryButtonStyle() -> some View {
        self
    }

    @ViewBuilder
    func detailHeroNativeSecondaryButtonStyle() -> some View {
        self
    }

    @ViewBuilder
    func detailHeroActionStackFrame(isCompactLayout: Bool) -> some View {
        self
    }
}

let detailHeroCompactActionWidthFraction: CGFloat = 0.6

let detailHeroRegularPrimaryWidth: CGFloat = 260

// MARK: - Actor Credit Card

struct ActorCreditCard: View {
    let person: PlexPersonReference
    /// The server this credit was read from; the person's page and avatar both
    /// have to be fetched from it, because person ids are per-server tag ids.
    let serverID: String?
    let plexService: PlexService

    var body: some View {
        NavigationLink(value: AppNavigationRoute.person(person, serverID: serverID)) {
            VStack(spacing: 8) {
                avatarImage(size: 72)
                personDetails(width: 80)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)

    }

    @ViewBuilder
    private func avatarImage(size: CGFloat) -> some View {
        let imageSize = Int(size.rounded())
        let artworkShape = RoundedRectangle(cornerRadius: PosterArtwork.cornerRadius, style: .continuous)

        Group {
            if let thumbPath = person.thumb {
                CineramaAsyncImage(url: plexService.imageURL(for: thumbPath, serverID: serverID, width: imageSize, height: imageSize)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        placeholder(size: size)
                    }
                }
            } else {
                placeholder(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(artworkShape)
        .contentShape(artworkShape)
    }

    private func placeholder(size: CGFloat) -> some View {
        ZStack {
            Color.cineramaSurface

            Image(systemName: "person.fill")
                .font(.system(size: size * 0.30, weight: .regular))
                .foregroundStyle(Color.cineramaTextSecondary)
        }
    }

    private func personDetails(width: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(person.name)
                .font(CineramaFont.cardSubtitle(style: .caption))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            if let roleName = person.roleName, !roleName.isEmpty {
                Text(roleName)
                    .font(CineramaFont.cardSubtitle(style: .caption2))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .lineLimit(1)
            }
        }
        .frame(width: width)
    }

    private var accessibilityLabel: String {
        if let roleName = person.roleName, !roleName.isEmpty {
            return "View \(person.name), \(roleName)"
        }

        return "View \(person.name)"
    }
}

struct DetailCastSection: View {
    let roles: [PlexRole]
    /// The server the item's metadata came from; its cast lives there too.
    let serverID: String?
    let plexService: PlexService
    var title = "Cast"
    var horizontalPadding: CGFloat = CineramaPosterMetrics.detailHorizontalPadding
    var maxVisibleRoles = 20

    var body: some View {
        let castSpacing: CGFloat = 12
        let castVerticalPadding: CGFloat = 0
        let headerSpacing: CGFloat = 12

        VStack(alignment: .leading, spacing: headerSpacing) {
            Text(title)
                .font(CineramaFont.sectionHeader(style: .headline))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: castSpacing) {
                    ForEach(Array(roles.prefix(maxVisibleRoles).enumerated()), id: \.offset) { _, role in
                        ActorCreditCard(
                            person: PlexPersonReference(role: role),
                            serverID: serverID,
                            plexService: plexService
                        )
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, castVerticalPadding)
            }
        }
    }
}

struct ExpandableSummaryText: View {
    static var defaultCollapsedLineLimit: Int {
        9
    }

    let text: String
    var collapsedLineLimit = ExpandableSummaryText.defaultCollapsedLineLimit
    var foregroundStyle = Color.primary.opacity(0.76)
    var allowsExpansion = true

    @State private var isExpanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var expandedHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                // Must stay identical to `measurementText` below, or the
                // expand/collapse height comparison stops matching the real text.
                .font(CineramaFont.body(style: .body))
                .foregroundStyle(foregroundStyle)
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .truncationMode(.tail)
                .overlay(alignment: .topLeading) {
                    ZStack {
                        measurementText(lineLimit: collapsedLineLimit) { height in
                            collapsedHeight = height
                        }

                        measurementText(lineLimit: nil) { height in
                            expandedHeight = height
                        }
                    }
                    .hidden()
                    .allowsHitTesting(false)
                }

            if allowsExpansion, isExpandable {
                Button(isExpanded ? "Show Less" : "Show More") {
                    isExpanded.toggle()
                }
                .font(CineramaFont.buttonLabel(style: .subheadline.weight(.semibold)))
                .foregroundStyle(Color.primary)
                .buttonStyle(.plain)
            }
        }
    }

    private var isExpandable: Bool {
        expandedHeight > collapsedHeight + 1
    }

    private func measurementText(
        lineLimit: Int?,
        onHeightChange: @escaping (CGFloat) -> Void
    ) -> some View {
        Text(text)
            // Keep in lockstep with the visible text's font above.
            .font(CineramaFont.body(style: .body))
            .lineSpacing(4)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            onHeightChange(proxy.size.height)
                        }
                        .onChange(of: proxy.size.height) { _, newHeight in
                            onHeightChange(newHeight)
                        }
                }
            }
    }
}
