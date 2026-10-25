import AppKit
import SwiftUI

struct HomeCinematicHeroLayout {
    var heroHeightFactor: CGFloat = 0.72
    var heroHeightRange: ClosedRange<CGFloat> = 520 ... 760
    var fillsContainerHeight: Bool = false
    var maxHeightToWidthRatio: CGFloat? = nil
    var maxContentWidth: CGFloat = 620
    var contentHorizontalPadding: CGFloat = 20
    var contentTopPadding: CGFloat = 64
    var contentBottomPaddingWithPager: CGFloat = 52
    var contentBottomPaddingWithoutPager: CGFloat = 28
    var actionsTopPadding: CGFloat = 0
    var actionsBottomPadding: CGFloat = 0
    var pagerHorizontalPadding: CGFloat = 20
    var pagerBottomPadding: CGFloat = 28
    /// Most pager pills shown at once. Past it the pager becomes a sliding
    /// window, see `HomeHeroPagerWindow`.
    var pagerMaxVisibleItems: Int = 7
    var titleFontSize: CGFloat = 42
    var titleLogoMaxWidth: CGFloat = 420
    var titleLogoMaxHeight: CGFloat = 108
    var backdropImageAlignment: Alignment = .center
    /// Scrim strength of `CineramaHeroBackdropOverlay`.
    var backdropOverlayStyle: CineramaHeroOverlayStyle = .standard
    /// Gap between the title (logo or text) and the lines under it. Movies have
    /// no episode title, so their block breathes a little wider.
    var titleBlockSpacingMovie: CGFloat = 18
    var titleBlockSpacingOther: CGFloat = 14
    var episodeTitleFont: Font = .title3.weight(.semibold)
    var metadataFont: Font = .subheadline.weight(.medium)
    var summaryFont: Font = .body
    var summaryLineLimit: Int = 3
    var summaryLineSpacing: CGFloat = 4

    static let desktop = HomeCinematicHeroLayout(
        heroHeightFactor: 0.90,
        heroHeightRange: 600 ... 900,
        maxContentWidth: 480,
        contentHorizontalPadding: 32,
        contentTopPadding: 64,
        contentBottomPaddingWithPager: 64,
        contentBottomPaddingWithoutPager: 36,
        actionsTopPadding: 6,
        pagerHorizontalPadding: 32,
        pagerBottomPadding: 32,
        pagerMaxVisibleItems: 9,
        titleFontSize: 48,
        titleLogoMaxWidth: 520,
        titleLogoMaxHeight: 136,
        backdropOverlayStyle: .cinematic,
        titleBlockSpacingMovie: 16,
        titleBlockSpacingOther: 12,
        episodeTitleFont: .title2.weight(.semibold),
        metadataFont: .callout.weight(.medium),
        summaryLineLimit: 2
    )

}

struct HomeCinematicHeroCallbacks {
    let pauseRotation: () -> Void
    let restartRotation: () -> Void
    let showPrevious: () -> Void
    let showNext: () -> Void
}

struct HomeCinematicHero: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlexService.self) private var plexService
    @Environment(PlaybackCoordinator.self) private var playback

    let items: [PlexItem]
    let viewModel: HomeViewModel
    let containerSize: CGSize
    let topInset: CGFloat
    var contentLeadingInset: CGFloat = 0
    var contentTrailingInset: CGFloat = 0
    var layout: HomeCinematicHeroLayout = .desktop
    var autoRotates = true
    var supportsDragNavigation = false
    let selectionResetRevision: Int
    let primaryAction: (PlexItem, HomeCinematicHeroCallbacks) -> AnyView
    var secondaryAction: ((PlexItem, HomeCinematicHeroCallbacks) -> AnyView)? = nil
    var detailsAction: ((PlexItem) -> Void)? = nil

    @State private var isHeroVisible = false
    @State private var currentHeroIndex = Self.initialHeroIndex
    @State private var heroRotationRevision = 0
    @State private var isHeroRotationPaused = false
    @State private var heroRotationStartedAt = Date()
    @State private var pausedHeroRotationProgress: Double?
    @State private var transitioningHeroIndex: Int?
    @State private var heroSlideProgress: CGFloat = 1
    @State private var heroSlideRevision = 0
    @State private var heroTransitionDirection: HeroTransitionDirection = .forward
    @State private var pendingHeroTransition: PendingHeroTransition?
    @State private var heroDragOffset: CGFloat = 0
    @State private var heroDragTargetIndex: Int?
    @State private var heroDragRevision = 0
    @State private var isHeroDragging = false

    private let heroRotationInterval: UInt64 = 7_000_000_000

    private let heroPressTransitionDuration: TimeInterval = 0.5

    var body: some View {
        let resolvedIndex = resolvedHeroIndex
        let heroWidth = pixelAlignedLength(containerSize.width)
        let rawHeroHeight: CGFloat = layout.fillsContainerHeight
            // Full-bleed: the caller already sized `containerSize` to the whole
            // display, top safe area included, so adding `topInset` again would
            // push the hero past the bottom of the screen.
            ? containerSize.height
            : min(
                max(containerSize.height * layout.heroHeightFactor, layout.heroHeightRange.lowerBound),
                layout.heroHeightRange.upperBound,
                layout.maxHeightToWidthRatio.map { containerSize.width * $0 } ?? .infinity
            ) + topInset
        let heroHeight = pixelAlignedLength(rawHeroHeight)
        let backdropWidth = Int(heroWidth.rounded(.up))
        let backdropHeight = Int(heroHeight.rounded(.up))
        let safeContentWidth = max(heroWidth - contentLeadingInset - contentTrailingInset, 0)
        let contentWidth = min(
            max(safeContentWidth - (layout.contentHorizontalPadding * 2) - 48, 0),
            layout.maxContentWidth
        )
        let titleLogoWidth = Int(min(contentWidth, layout.titleLogoMaxWidth).rounded(.up))
        let titleLogoHeight = Int(layout.titleLogoMaxHeight.rounded(.up))

        let baseHero = ZStack(alignment: .bottomLeading) {
            heroSlides(
                resolvedIndex: resolvedIndex,
                heroWidth: heroWidth,
                heroHeight: heroHeight,
                backdropWidth: backdropWidth,
                backdropHeight: backdropHeight,
                contentWidth: contentWidth
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        // An overlay, not a ZStack sibling: the pager must never size the
        // hero. As a sibling, a pager wider than the screen (one pill per
        // Continue Watching item) widened the whole ZStack and pushed the
        // centred title block and Play button off the right edge.
        .overlay(alignment: heroContentBlockAlignment) {
            if items.count > 1 {
                heroPager(currentIndex: resolvedIndex)
                    .padding(.leading, contentLeadingInset + layout.pagerHorizontalPadding)
                    .padding(.trailing, contentTrailingInset + layout.pagerHorizontalPadding)
                    .padding(.bottom, layout.pagerBottomPadding)
            }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder")
                Text("CINEMA VIEWPORT")
                    .tracking(2)
                Spacer(minLength: 0)
                Text(String(format: "%02d / %02d", resolvedIndex + 1, items.count))
                    .monospacedDigit()
            }
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(LinearGradient(colors: [.black.opacity(0.65), .clear],
                                       startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .background {
            HomeHeroArrowKeys { showsPrevious in
                guard isHeroVisible, items.count > 1, !playback.showPlayer,
                      scenePhase == .active, !isHeroDragging,
                      heroDragTargetIndex == nil else { return false }
                if showsPrevious { showPreviousHero() }
                else { showNextHero() }
                return true
            }
            .allowsHitTesting(false)
        }
        .onAppear { isHeroVisible = true }
        .onDisappear { isHeroVisible = false }
        .onChange(of: heroItemIDs) { _, ids in
            guard !ids.isEmpty else {
                resetHeroSelection(restartRotation: false)
                return
            }

            resetHeroSelection()
        }
        .onChange(of: selectionResetRevision) { _, _ in
            resetHeroSelection()
        }
        .onChange(of: playback.showPlayer) { _, isShowing in
            // The player presents as a full-screen cover, which does not change
            // scenePhase, so the rotation timer would otherwise keep advancing the
            // hero behind it. Pause while playing and restart fresh on return so we
            // come back to the hero the user launched from.
            if isShowing {
                pauseHeroRotation()
            } else {
                restartHeroRotation()
            }
        }
        .task(id: heroRotationSeed) {
            await rotateHeroIfNeeded()
        }
        .task(id: heroBackdropPrefetchSeed(width: backdropWidth, height: backdropHeight)) {
            await preloadHeroBackdropImages(width: backdropWidth, height: backdropHeight)
        }
        .task(id: heroTitlePrefetchSeed(width: titleLogoWidth, height: titleLogoHeight)) {
            await preloadHeroTitleImages(width: titleLogoWidth, height: titleLogoHeight)
        }

        if supportsDragNavigation {
            return AnyView(
                baseHero
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                handleHeroDragChanged(value)
                            }
                            .onEnded { value in
                                handleHeroDragEnded(value, heroWidth: heroWidth)
                            }
                    )
            )
        } else {
            return AnyView(baseHero)
        }
    }

    @ViewBuilder
    private func heroSlides(
        resolvedIndex: Int,
        heroWidth: CGFloat,
        heroHeight: CGFloat,
        backdropWidth: Int,
        backdropHeight: Int,
        contentWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let backgroundHeroIndex,
               items.indices.contains(backgroundHeroIndex) {
                heroSlide(
                    item: items[backgroundHeroIndex],
                    heroHeight: heroHeight,
                    backdropWidth: backdropWidth,
                    backdropHeight: backdropHeight,
                    contentWidth: contentWidth,
                    reservesPagerSpace: items.count > 1
                )
                .offset(x: backgroundHeroOffset(width: heroWidth))
                .id("background-\(items[backgroundHeroIndex].id.storageKey)")
                .zIndex(0)
            }

            if items.indices.contains(resolvedIndex) {
                heroSlide(
                    item: items[resolvedIndex],
                    heroHeight: heroHeight,
                    backdropWidth: backdropWidth,
                    backdropHeight: backdropHeight,
                    contentWidth: contentWidth,
                    reservesPagerSpace: items.count > 1
                )
                .offset(x: foregroundHeroOffset(width: heroWidth))
                .id("foreground-\(items[resolvedIndex].id.storageKey)")
                .zIndex(1)
            }
        }
    }


    private var actionCallbacks: HomeCinematicHeroCallbacks {
        HomeCinematicHeroCallbacks(
            pauseRotation: pauseHeroRotation,
            restartRotation: restartHeroRotation,
            showPrevious: showPreviousHero,
            showNext: showNextHero
        )
    }

    private static var initialHeroIndex: Int {
        0
    }

    private var resolvedHeroIndex: Int {
        guard !items.isEmpty else { return 0 }
        return min(currentHeroIndex, items.count - 1)
    }

    private var heroItemIDs: [String] {
        items.map(\.id.storageKey)
    }

    private var visibleItemKey: String? {
        items.isEmpty ? nil : items[resolvedHeroIndex].id.storageKey
    }

    private func pixelAlignedLength(_ length: CGFloat) -> CGFloat {
        let scale = displayScale
        guard scale > 0, length.isFinite else { return length }
        return (length * scale).rounded(.up) / scale
    }

    private var heroRotationDuration: TimeInterval {
        Double(heroRotationInterval) / 1_000_000_000
    }

    private var heroRotationSeed: String {
        [
            heroItemIDs.joined(separator: "|"),
            String(heroRotationRevision),
            String(accessibilityReduceMotion),
            String(scenePhase == .active),
            String(isHeroRotationPaused),
            String(autoRotates),
            String(isHeroDragging),
            String(isRotationSuspended),
        ].joined(separator: "::")
    }

    private var isRotationSuspended: Bool {
        false
    }

    private var backgroundHeroIndex: Int? {
        if isHeroDragActive {
            return heroDragTargetIndex
        }

        return transitioningHeroIndex
    }

    private var isHeroDragActive: Bool {
        isHeroDragging || heroDragTargetIndex != nil || heroDragOffset != 0
    }

    private var isHeroDragSettling: Bool {
        heroDragTargetIndex != nil && !isHeroDragging
    }

    private func heroSlide(
        item: PlexItem,
        heroHeight: CGFloat,
        backdropWidth: Int,
        backdropHeight: Int,
        contentWidth: CGFloat,
        reservesPagerSpace: Bool
    ) -> some View {
        let metadata = viewModel.heroMetadata(for: item)

        return ZStack(alignment: .bottomLeading) {
            ZStack {
                heroBackdrop(
                    for: item,
                    width: backdropWidth,
                    height: backdropHeight,
                    heroHeight: heroHeight
                )

                CineramaHeroBackdropOverlay(style: layout.backdropOverlayStyle)
            }

            VStack(alignment: heroContentHorizontalAlignment, spacing: heroHeight < 620 ? 12 : 20) {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.on.rectangle")
                    Text(item.posterProgress == nil ? "FEATURED IN YOUR LIBRARY" : "CONTINUE WATCHING")
                        .tracking(2)
                }
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.black.opacity(0.35), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.75))

                VStack(alignment: heroContentHorizontalAlignment, spacing: heroTitleBlockSpacing(for: item)) {
                    heroTitle(for: item, contentWidth: contentWidth)

                    if let episodeTitle = viewModel.heroEpisodeTitle(for: item) {
                        Text(episodeTitle)
                            .font(layout.episodeTitleFont)
                            .foregroundStyle(Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(heroTextAlignment)
                            .frame(maxWidth: contentWidth, alignment: heroContentFrameAlignment)
                    }

                    if !metadata.isEmpty {
                        Text(metadata.joined(separator: " · "))
                            .font(layout.metadataFont)
                            .foregroundStyle(Color.primary.opacity(0.78))
                            .lineLimit(2)
                            .multilineTextAlignment(heroTextAlignment)
                            .frame(maxWidth: contentWidth, alignment: heroContentFrameAlignment)
                    }
                }

                if showsHeroSummary, let summary = viewModel.heroSummary(for: item) {
                    Text(summary)
                        .font(layout.summaryFont)
                        .foregroundStyle(Color.primary.opacity(0.76))
                        .lineLimit(layout.summaryLineLimit)
                        .lineSpacing(layout.summaryLineSpacing)
                        .multilineTextAlignment(heroTextAlignment)
                        .frame(maxWidth: contentWidth, alignment: heroContentFrameAlignment)
                }

                heroActions(for: item)
                    .padding(.top, layout.actionsTopPadding)
                    .padding(.bottom, layout.actionsBottomPadding)
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.black.opacity(reduceTransparency ? 1 : 0.38))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.03)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 0.75
                            )
                    }
            }
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: contentWidth + 48, alignment: .leading)
            .padding(.leading, contentLeadingInset + layout.contentHorizontalPadding)
            .padding(.trailing, contentTrailingInset + layout.contentHorizontalPadding)
            .padding(.bottom, reservesPagerSpace ? layout.contentBottomPaddingWithPager : layout.contentBottomPaddingWithoutPager)
            .padding(.top, topInset + layout.contentTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: heroContentBlockAlignment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func heroTitleBlockSpacing(for item: PlexItem) -> CGFloat {
        item.type == .movie ? layout.titleBlockSpacingMovie : layout.titleBlockSpacingOther
    }

    private var showsHeroSummary: Bool {
        true
    }

    private var centersHeroContent: Bool {
        false
    }

    private var heroContentHorizontalAlignment: HorizontalAlignment {
        centersHeroContent ? .center : .leading
    }

    private var heroContentFrameAlignment: Alignment {
        centersHeroContent ? .center : .leading
    }

    private var heroContentBlockAlignment: Alignment {
        centersHeroContent ? .bottom : .bottomLeading
    }

    private var heroTextAlignment: TextAlignment {
        centersHeroContent ? .center : .leading
    }

    @ViewBuilder
    private func heroTitle(for item: PlexItem, contentWidth: CGFloat) -> some View {
        let logoWidth = min(contentWidth, layout.titleLogoMaxWidth)
        let logoHeight = layout.titleLogoMaxHeight
        if item.clearLogo != nil {
            heroTitleArtwork(for: item, width: logoWidth, height: logoHeight)
        } else {
            heroTitleFallback(for: item)
        }
    }

    @ViewBuilder
    private func heroTitleArtwork(for item: PlexItem, width: CGFloat, height: CGFloat) -> some View {
        heroTitleFallback(for: item)
    }

    private func heroTitleFallback(for item: PlexItem) -> some View {
        // When a show/movie has no title-logo artwork, the title renders as text.
        // Keep the title white against the dark panel. The panel also supplies
        // a dark environment for episode title, metadata, summary and actions.
        Text(viewModel.displayTitle(for: item))
            .font(.system(size: layout.titleFontSize, weight: .bold, design: .default))
            .foregroundStyle(Color.white)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.24), radius: 10, y: 4)
            .multilineTextAlignment(heroTextAlignment)
            .frame(maxWidth: .infinity, alignment: heroContentFrameAlignment)
    }

    @ViewBuilder
    private func heroActions(for item: PlexItem) -> some View {
        let primary = primaryAction(item, actionCallbacks)
        let secondary = secondaryAction?(item, actionCallbacks)

        if let secondary {
            HStack(spacing: 16) {
                primary
                secondary
            }
        } else {
            primary
        }
    }

    @ViewBuilder
    private func heroPager(currentIndex: Int) -> some View {
        if autoRotates {
            TimelineView(.periodic(from: .now, by: 0.05)) { timeline in
                pagerContent(currentIndex: currentIndex, date: timeline.date)
            }
        } else {
            pagerContent(currentIndex: currentIndex, date: nil)
        }
    }

    @ViewBuilder
    private func pagerContent(currentIndex: Int, date: Date?) -> some View {
        let window = HomeHeroPagerWindow(
            count: items.count,
            currentIndex: currentIndex,
            maxVisible: layout.pagerMaxVisibleItems
        )

        let pills = HStack(spacing: 8) {
            ForEach(Array(window.range), id: \.self) { index in
                Button {
                    selectHero(at: index)
                } label: {
                    HomeHeroPagerPill(
                        isActive: index == currentIndex,
                        progress: pagerProgress(for: index, currentIndex: currentIndex, date: date)
                    )
                    .scaleEffect(window.scale(for: index))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: window.range)

        // One adjustable element, like UIPageControl, instead of a button per
        // item that the window may be hiding.
        pills
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Continue Watching"))
            .accessibilityValue(
                Text("\(viewModel.displayTitle(for: items[currentIndex])), \(currentIndex + 1) of \(items.count)")
            )
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    selectHero(at: (currentIndex + 1) % items.count)
                case .decrement:
                    selectHero(at: (currentIndex - 1 + items.count) % items.count)
                @unknown default:
                    break
                }
            }
    }

    private func pagerProgress(for index: Int, currentIndex: Int, date: Date?) -> Double {
        guard index == currentIndex else { return 0 }
        guard autoRotates, let date else { return 1 }
        return heroRotationProgress(at: date)
    }

    private func rotateHeroIfNeeded() async {
        guard autoRotates,
              heroItemIDs.count > 1,
              !accessibilityReduceMotion,
              scenePhase == .active,
              !isHeroRotationPaused,
              !isRotationSuspended else {
            return
        }

        do {
            try await Task.sleep(nanoseconds: remainingHeroRotationNanoseconds(at: Date()))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        await MainActor.run {
            guard autoRotates,
                  heroItemIDs.count > 1,
                  !isHeroRotationPaused,
                  !isRotationSuspended else { return }

            moveHero(
                to: (currentHeroIndex + 1) % heroItemIDs.count,
                direction: .forward,
                duration: 0.42
            )
            restartHeroRotation()
        }
    }

    private func selectHero(at index: Int) {
        guard index != currentHeroIndex else {
            restartHeroRotation()
            return
        }

        restartHeroRotation()
        moveHero(
            to: index,
            direction: resolvedHeroTransitionDirection(
                from: currentHeroIndex,
                to: index,
                itemCount: heroItemIDs.count
            ),
            duration: heroPressTransitionDuration
        )
    }

    private func restartHeroRotation() {
        guard autoRotates else { return }
        // Suspended, a fresh interval waits at the start until focus is back.
        isHeroRotationPaused = isRotationSuspended
        pausedHeroRotationProgress = isRotationSuspended ? 0 : nil
        heroRotationStartedAt = Date()
        heroRotationRevision += 1
    }

    private func pauseHeroRotation() {
        guard autoRotates, !isHeroRotationPaused else { return }
        isHeroRotationPaused = true
        pausedHeroRotationProgress = heroRotationProgress(at: Date())
        heroRotationRevision += 1
    }

    private func handleHeroDragChanged(_ value: DragGesture.Value) {
        handleHeroHorizontalNavigationChanged(
            horizontalOffset: value.translation.width,
            verticalOffset: value.translation.height
        )
    }

    private func handleHeroDragEnded(_ value: DragGesture.Value, heroWidth: CGFloat) {
        handleHeroHorizontalNavigationEnded(
            horizontalOffset: value.translation.width,
            verticalOffset: value.translation.height,
            predictedHorizontalOffset: value.predictedEndTranslation.width,
            heroWidth: heroWidth
        )
    }

    private func handleHeroHorizontalNavigationChanged(
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat = 0
    ) {
        guard supportsDragNavigation,
              heroItemIDs.count > 1,
              transitioningHeroIndex == nil,
              !isHeroDragSettling else {
            return
        }

        guard abs(horizontalOffset) > abs(verticalOffset),
              abs(horizontalOffset) > 8 else {
            return
        }

        if !isHeroDragging {
            pauseHeroRotation()
            isHeroDragging = true
        }

        heroDragTargetIndex = adjacentHeroIndex(forDragOffset: horizontalOffset)
        heroDragOffset = resolvedHeroDragOffset(for: horizontalOffset)
    }

    private func handleHeroIndirectScrollChanged(horizontalOffset: CGFloat) {
        handleHeroHorizontalNavigationChanged(horizontalOffset: horizontalOffset)
    }

    private func handleHeroIndirectScrollEnded(
        horizontalOffset: CGFloat,
        predictedHorizontalOffset: CGFloat,
        heroWidth: CGFloat
    ) {
        let commitThreshold = max(min(heroWidth * 0.08, 96), 32)

        handleHeroHorizontalNavigationEnded(
            horizontalOffset: horizontalOffset,
            predictedHorizontalOffset: predictedHorizontalOffset,
            heroWidth: heroWidth,
            commitThreshold: commitThreshold
        )
    }

    private func handleHeroHorizontalNavigationEnded(
        horizontalOffset: CGFloat,
        verticalOffset: CGFloat = 0,
        predictedHorizontalOffset: CGFloat,
        heroWidth: CGFloat,
        commitThreshold: CGFloat? = nil
    ) {
        guard supportsDragNavigation, isHeroDragActive else { return }

        let horizontalDrag = abs(horizontalOffset) > abs(verticalOffset)
        let projectedOffset = resolvedHeroDragOffset(for: predictedHorizontalOffset)
        let commitThreshold = commitThreshold ?? max(heroWidth * 0.18, 56)
        let targetIndex = heroDragTargetIndex

        if horizontalDrag,
           let targetIndex,
           abs(projectedOffset) >= commitThreshold {
            completeHeroDragTransition(to: targetIndex, heroWidth: heroWidth)
        } else {
            cancelHeroDragTransition()
        }
    }


    private func showPreviousHero() {
        guard heroItemIDs.count > 1 else { return }

        let heroCount = heroItemIDs.count
        restartHeroRotation()
        moveHero(
            to: (currentHeroIndex - 1 + heroCount) % heroCount,
            direction: .backward,
            duration: heroPressTransitionDuration
        )
    }

    private func showNextHero() {
        guard heroItemIDs.count > 1 else { return }

        let heroCount = heroItemIDs.count
        restartHeroRotation()
        moveHero(
            to: (currentHeroIndex + 1) % heroCount,
            direction: .forward,
            duration: heroPressTransitionDuration
        )
    }

    private func heroRotationProgress(at date: Date) -> Double {
        if let pausedHeroRotationProgress {
            return max(0, min(pausedHeroRotationProgress, 1))
        }

        let elapsed = date.timeIntervalSince(heroRotationStartedAt)
        guard heroRotationDuration > 0 else { return 0 }
        return max(0, min(elapsed / heroRotationDuration, 1))
    }

    private func remainingHeroRotationNanoseconds(at date: Date) -> UInt64 {
        let progress = heroRotationProgress(at: date)
        let remaining = max(0, 1 - progress) * heroRotationDuration
        return UInt64((remaining * 1_000_000_000).rounded())
    }

    private func resetHeroSlideState() {
        heroSlideRevision += 1
        pendingHeroTransition = nil
        transitioningHeroIndex = nil
        heroSlideProgress = 1
    }

    private func resetHeroDragState() {
        heroDragRevision += 1
        heroDragOffset = 0
        heroDragTargetIndex = nil
        isHeroDragging = false
    }

    private func resetHeroSelection(restartRotation: Bool = true) {
        resetHeroSlideState()
        resetHeroDragState()
        currentHeroIndex = Self.initialHeroIndex

        if restartRotation {
            restartHeroRotation()
        }
    }

    private func heroBackdropPrefetchSeed(width: Int, height: Int) -> String {
        [
            items.map(\.id.storageKey).joined(separator: "|"),
            "\(width)x\(height)"
        ].joined(separator: "::")
    }

    private func heroTitlePrefetchSeed(width: Int, height: Int) -> String {
        [
            items.map { "\($0.id.storageKey):\($0.clearLogo ?? "")" }.joined(separator: "|"),
            "\(width)x\(height)"
        ].joined(separator: "::")
    }

    private func preloadHeroBackdropImages(width: Int, height: Int) async {
    }

    private func preloadHeroTitleImages(width: Int, height: Int) async {
    }

    @ViewBuilder
    private func heroBackdrop(
        for item: PlexItem,
        width: Int,
        height: Int,
        heroHeight: CGFloat
    ) -> some View {
        let imageAlignment = heroBackdropImageAlignment

        DetailHeroBackdrop(
            imageURL: viewModel.heroBackgroundURL(
                for: item,
                width: width,
                height: height
            ),
            height: heroHeight,
            imageAlignment: imageAlignment
        )
    }

    private var heroBackdropImageAlignment: Alignment {
        layout.backdropImageAlignment
    }

    private func moveHero(to index: Int, direction: HeroTransitionDirection, duration: TimeInterval) {
        guard items.indices.contains(index), index != currentHeroIndex else { return }

        if transitioningHeroIndex != nil {
            pendingHeroTransition = PendingHeroTransition(
                index: index,
                direction: direction,
                duration: duration
            )
            return
        }

        resetHeroDragState()

        let previousIndex = currentHeroIndex
        let slideRevision = heroSlideRevision + 1

        heroSlideRevision = slideRevision
        heroTransitionDirection = direction
        transitioningHeroIndex = previousIndex
        currentHeroIndex = index
        heroSlideProgress = 0

        Task { @MainActor in
            await Task.yield()
            guard heroSlideRevision == slideRevision else { return }

            withAnimation(heroSlideAnimation(duration: duration)) {
                heroSlideProgress = 1
            }

            try? await Task.sleep(
                nanoseconds: UInt64((duration * 1_000_000_000).rounded())
            )

            guard heroSlideRevision == slideRevision else { return }
            let pendingTransition = pendingHeroTransition
            pendingHeroTransition = nil
            transitioningHeroIndex = nil
            heroSlideProgress = 1

            if let pendingTransition {
                moveHero(
                    to: pendingTransition.index,
                    direction: pendingTransition.direction,
                    duration: pendingTransition.duration
                )
            }
        }
    }

    private func heroSlideAnimation(duration: TimeInterval) -> Animation {
        .easeInOut(duration: duration)
    }

    private func heroSlideOffset(for role: HeroSlideRole, width: CGFloat) -> CGFloat {
        guard transitioningHeroIndex != nil else { return 0 }

        switch (heroTransitionDirection, role) {
        case (.forward, .outgoing):
            return -width * heroSlideProgress
        case (.forward, .incoming):
            return width * (1 - heroSlideProgress)
        case (.backward, .outgoing):
            return width * heroSlideProgress
        case (.backward, .incoming):
            return -width * (1 - heroSlideProgress)
        }
    }

    private func foregroundHeroOffset(width: CGFloat) -> CGFloat {
        if isHeroDragActive {
            return heroDragOffset
        }

        return heroSlideOffset(for: .incoming, width: width)
    }

    private func backgroundHeroOffset(width: CGFloat) -> CGFloat {
        if isHeroDragActive {
            guard let heroDragTargetIndex,
                  items.indices.contains(heroDragTargetIndex) else {
                return 0
            }

            if heroDragOffset < 0 {
                return width + heroDragOffset
            } else {
                return -width + heroDragOffset
            }
        }

        return heroSlideOffset(for: .outgoing, width: width)
    }

    private func adjacentHeroIndex(forDragOffset offset: CGFloat) -> Int? {
        guard heroItemIDs.count > 1 else { return nil }

        let heroCount = heroItemIDs.count

        if offset < 0 {
            return (currentHeroIndex + 1) % heroCount
        }

        if offset > 0 {
            return (currentHeroIndex - 1 + heroCount) % heroCount
        }

        return nil
    }

    private func resolvedHeroDragOffset(for rawOffset: CGFloat) -> CGFloat {
        guard rawOffset != 0 else { return 0 }

        guard adjacentHeroIndex(forDragOffset: rawOffset) != nil else {
            return rawOffset * 0.18
        }

        return rawOffset
    }

    private func completeHeroDragTransition(to index: Int, heroWidth: CGFloat) {
        guard heroWidth > 0 else {
            currentHeroIndex = index
            resetHeroDragState()
            restartHeroRotation()
            return
        }

        let dragRevision = heroDragRevision + 1
        let finalOffset = heroDragOffset < 0 ? -heroWidth : heroWidth
        let settleDuration = 0.24

        heroDragRevision = dragRevision
        isHeroDragging = false

        withAnimation(.easeOut(duration: settleDuration)) {
            heroDragOffset = finalOffset
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64((settleDuration * 1_000_000_000).rounded()))

            await MainActor.run {
                guard heroDragRevision == dragRevision else { return }
                currentHeroIndex = index
                resetHeroDragState()
                restartHeroRotation()
            }
        }
    }

    private func cancelHeroDragTransition() {
        let dragRevision = heroDragRevision + 1
        let settleDuration = 0.24

        heroDragRevision = dragRevision
        isHeroDragging = false

        withAnimation(.easeOut(duration: settleDuration)) {
            heroDragOffset = 0
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64((settleDuration * 1_000_000_000).rounded()))

            await MainActor.run {
                guard heroDragRevision == dragRevision else { return }
                resetHeroDragState()
                restartHeroRotation()
            }
        }
    }

    private func resolvedHeroTransitionDirection(
        from currentIndex: Int,
        to nextIndex: Int,
        itemCount: Int
    ) -> HeroTransitionDirection {
        guard itemCount > 1, currentIndex != nextIndex else { return .forward }

        let forwardDistance = nextIndex >= currentIndex
            ? nextIndex - currentIndex
            : itemCount - currentIndex + nextIndex
        let backwardDistance = currentIndex >= nextIndex
            ? currentIndex - nextIndex
            : currentIndex + itemCount - nextIndex

        return forwardDistance <= backwardDistance ? .forward : .backward
    }
}

private enum HeroTransitionDirection {
    case forward
    case backward
}

private struct PendingHeroTransition {
    let index: Int
    let direction: HeroTransitionDirection
    let duration: TimeInterval
}

private enum HeroSlideRole {
    case outgoing
    case incoming
}

/// The hero responds to unmodified arrows under the pointer without taking
/// keyboard focus from native controls or installing global keyboard shortcuts.
private struct HomeHeroArrowKeys: NSViewRepresentable {
    let navigate: (Bool) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(navigate: navigate) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.navigate = navigate
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var navigate: (Bool) -> Bool
        private weak var view: NSView?
        private var monitor: Any?

        init(navigate: @escaping (Bool) -> Bool) { self.navigate = navigate }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, event.keyCode == 123 || event.keyCode == 124,
                          event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                          let view = self.view, !view.isHiddenOrHasHiddenAncestor,
                          let window = view.window, event.window === window,
                          window.isKeyWindow, window.attachedSheet == nil,
                          !(window.firstResponder is NSTextView),
                          !(window.firstResponder is NSTextField) else { return false }
                    let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                    guard view.visibleRect.contains(point) else { return false }
                    return self.navigate(event.keyCode == 123)
                }
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
