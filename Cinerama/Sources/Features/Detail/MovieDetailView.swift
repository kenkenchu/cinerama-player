import SwiftUI

struct MovieDetailView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(UserPreferences.self) private var preferences
    @State private var viewModel: MovieDetailViewModel
    @State private var showSubtitleSearch = false

    private let horizontalPadding: CGFloat = CineramaPosterMetrics.detailHorizontalPadding

    init(
        id: PlexItemID,
        plexService: PlexService,
        downloadManager: DownloadManager? = nil,
        offlinePlaybackSyncManager: OfflinePlaybackSyncManager? = nil
    ) {
        _viewModel = State(initialValue: MovieDetailViewModel(
            id: id,
            plexService: plexService,
            downloadManager: downloadManager,
            offlinePlaybackSyncManager: offlinePlaybackSyncManager
        ))
    }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            if viewModel.isLoading && viewModel.details == nil {
                FeatureLoadingView()
            } else if let error = viewModel.error, viewModel.details == nil {
                FeatureErrorView(message: error) {
                    Task { await viewModel.loadDetails() }
                }
            } else if let details = viewModel.details {
                contentView(details)
            }
        }

        .toolbarColorScheme(.dark, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .task {
            await viewModel.loadDetails()
        }
        .onChange(of: playback.showPlayer) { _, isShowing in
            if !isShowing {
                Task { await viewModel.refreshDetails() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, viewModel.details != nil else { return }
            Task { await viewModel.refreshDetails() }
        }
        .detailSubtitleSearchPresentation(isPresented: $showSubtitleSearch) {
            viewModel.makeSubtitleSearchViewModel(
                preferredLanguageCode: preferences.defaultSubtitleLanguage
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func contentView(_ details: PlexMediaDetails) -> some View {
        GeometryReader { geometry in
            let heroBackgroundWidth: CGFloat = {
                geometry.size.width
            }()
            let heroBackgroundLeadingInset: CGFloat = {
                0
            }()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection(
                        details,
                        topInset: geometry.safeAreaInsets.top,
                        containerWidth: heroBackgroundWidth,
                        containerHeight: geometry.size.height,
                        backgroundLeadingInset: heroBackgroundLeadingInset
                    )
                    if detailShowsSynopsisBelowHero(for: sizeClass), let summary = details.summary, !summary.isEmpty {
                        summarySection(summary)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 40)
                    }
                    if let offlineBannerText = viewModel.offlineBannerText {
                        OfflineMetadataBanner(message: offlineBannerText)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 24)
                    }
                    if let roles = details.roles, !roles.isEmpty {
                        DetailCastSection(
                            roles: roles,
                            serverID: viewModel.serverID,
                            plexService: plexService
                        )
                            .padding(.top, 40)
                    }
                    mediaInfoSection()
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 40)
                        .padding(.bottom, 56)
                }
                .padding(.top, -geometry.safeAreaInsets.top)
                .frame(width: geometry.size.width, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollIndicators(.hidden)

        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func heroSection(
        _ details: PlexMediaDetails,
        topInset: CGFloat,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        backgroundLeadingInset: CGFloat = 0
    ) -> some View {
        let heroBase = min(max(containerHeight * 0.72, 520), 760)
        let heroHeight = heroBase + topInset
        DetailHeroSection(
            backdropURL: viewModel.backdropURL(width: Int(containerWidth.rounded(.up)), height: Int(heroHeight.rounded(.up))),
            titleArtworkURL: viewModel.titleLogoURL(width: Int((containerWidth * 0.45).rounded(.up)), height: 128),
            title: details.title,
            descriptionText: details.summary,
            topInset: topInset,
            containerWidth: containerWidth,
            backgroundLeadingInset: backgroundLeadingInset,
            heroBaseHeight: heroBase
        ) {
            VStack(alignment: detailHeroContentAlignment(for: sizeClass), spacing: 6) {
                metadataTagline(details)
                heroMetadata(details)
            }
            .multilineTextAlignment(detailHeroTextAlignment(for: sizeClass))
        } actions: {
            actionButtons(details)
        }
    }

    @ViewBuilder
    private func metadataTagline(_ details: PlexMediaDetails) -> some View {
        let parts = [
            details.year.map(String.init),
            details.contentRating,
            viewModel.formattedDuration,
        ].compactMap { $0 }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(CineramaFont.metadata(style: .subheadline.weight(.medium)))
                .foregroundStyle(Color.primary.opacity(0.78))
        }
    }

    @ViewBuilder
    private func heroMetadata(_ details: PlexMediaDetails) -> some View {
        if let genres = viewModel.genreText {
            Text(genres)
                .font(CineramaFont.caption(style: .caption))
                .foregroundStyle(Color.primary.opacity(0.72))
        }

        if let rating = details.rating {
            HStack(spacing: 12) {
                ratingBadge(
                    icon: "star.fill",
                    value: String(format: "%.1f", rating),
                    color: .yellow
                )
                if let audience = details.audienceRating {
                    ratingBadge(
                        icon: "person.fill",
                        value: String(format: "%.0f%%", audience * 10),
                        color: Color.primary.opacity(0.72)
                    )
                }
            }
        }

        if let director = viewModel.directorText {
            Text("Directed by \(director)")
                .font(CineramaFont.caption(style: .caption))
                .foregroundStyle(Color.primary.opacity(0.72))
        }

        if let studio = details.studio {
            Text(studio)
                .font(CineramaFont.caption(style: .caption))
                .foregroundStyle(Color.primary.opacity(0.72))
        }
    }

    private func ratingBadge(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(CineramaFont.glyphSmall(style: .caption2))
                .foregroundStyle(color)
            Text(value)
                .font(CineramaFont.metadata(style: .subheadline).monospacedDigit())
                .foregroundStyle(Color.primary.opacity(0.84))
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func actionButtons(_ details: PlexMediaDetails) -> some View {
        // Primary fills the stack width; secondary row is centered beneath it.
        VStack(alignment: .center, spacing: detailHeroActionSpacing) {
            playButton(details)

            HStack(spacing: detailHeroActionSpacing) {
                downloadButton(details)
                watchedButton()
            }
        }
        .detailHeroActionStackFrame(isCompactLayout: usesFullWidthActionButtons)
    }

    private func playButton(_ details: PlexMediaDetails) -> some View {
        Button {
            guard !viewModel.isUsingCachedData || viewModel.isPlayableOffline else { return }
            Task {
                await playback.play(
                    id: details.id,
                    resumeOffsetMilliseconds: details.viewOffset,
                    resumeOffsetDurationMilliseconds: details.duration,
                    placeholder: PlaybackPlaceholder(details: details)
                )
            }
        } label: {
            DetailHeroPrimaryActionButtonLabel(
                title: viewModel.formattedResume.map { "Resume from \($0)" } ?? "Play",
                systemImage: "play.fill",
                fillsWidth: fillsActionWidth
            )
        }
        .detailHeroNativePrimaryButtonStyle()
        .disabled(viewModel.isUsingCachedData && !viewModel.isPlayableOffline)
        .contextMenu {
            if !viewModel.isUsingCachedData || viewModel.isPlayableOffline {
                PlayVersionContextMenu(versions: details.media) { version in
                    Task {
                        await playback.playVersion(
                            id: details.id,
                            mediaID: version.id,
                            resumeOffsetMilliseconds: details.viewOffset,
                            placeholder: PlaybackPlaceholder(details: details)
                        )
                    }
                }
            }

            if viewModel.canDownloadSubtitles {
                Button {
                    showSubtitleSearch = true
                } label: {
                    Label("Download Subtitles", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    private func downloadButton(_ details: PlexMediaDetails) -> some View {
        DownloadActionButton(
            id: details.id,
            type: .movie,
            iconOnly: true
        )
    }

    @ViewBuilder
    private func subtitleSearchButton() -> some View {
        EmptyView()
    }

    private func watchedButton() -> some View {
        Button {
            Task { await viewModel.toggleWatched() }
        } label: {
            DetailHeroSecondaryIconLabel(systemImage: viewModel.isWatched ? "eye.slash" : "eye")
        }
        .detailHeroNativeSecondaryButtonStyle()
        .accessibilityLabel(viewModel.isWatched ? "Mark Unwatched" : "Mark Watched")
    }

    private var usesFullWidthActionButtons: Bool {
        usesFullWidthDetailActionButtons(for: sizeClass)
    }

    private var fillsActionWidth: Bool {
        true
    }

    // MARK: - Summary

    @ViewBuilder
    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synopsis")
                .font(CineramaFont.sectionHeader(style: .headline))
                .foregroundStyle(Color.primary)

            Text(summary)
                .font(CineramaFont.body(style: .body))
                .foregroundStyle(Color.primary.opacity(0.76))
                .lineSpacing(4)
        }
    }

    // MARK: - Media Info

    @ViewBuilder
    private func mediaInfoSection() -> some View {
        if let info = viewModel.mediaInfo {
            VStack(alignment: .leading, spacing: 8) {
                Text("Media")
                    .font(CineramaFont.sectionHeader(style: .headline))
                    .foregroundStyle(Color.primary)

                Text(info)
                    .font(CineramaFont.metadata(style: .subheadline).monospaced())
                    .foregroundStyle(Color.primary.opacity(0.76))
            }
        }
    }
}
