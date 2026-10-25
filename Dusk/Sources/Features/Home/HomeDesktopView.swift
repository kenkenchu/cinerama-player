import SwiftUI

struct HomeDesktopView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var path: NavigationPath

    let viewModel: HomeViewModel
    /// Enabled servers that are currently unreachable. Only used for the quiet
    /// inline note; Home never names the server a row came from, because with
    /// every server merged into one screen that would be noise.
    let offlineServerNames: [String]
    let recentlyAddedInlineItemLimit: Int
    let heroSelectionResetRevision: Int
    let liveTVViewModel: LiveTVViewModel
    let showsLiveTV: Bool
    let playLiveTV: (PlexLiveChannel, PlexLiveProgram?, PlexLiveTVLineup) -> Void
    let play: (PlexItem) -> Void

    var body: some View {
        content
            .navigationTitle("Home")
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SearchToolbarLink()
                }
            }
    }

    private var content: some View {
        GeometryReader { geometry in
            let heroItems = viewModel.heroItems()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HomeDeckHeader(featuredCount: heroItems.count)

                    if !heroItems.isEmpty {
                        HomeCinematicHero(
                            items: heroItems,
                            viewModel: viewModel,
                            containerSize: CGSize(width: max(0, geometry.size.width - 40), height: geometry.size.height),
                            topInset: 0,
                            layout: heroLayout(for: geometry.size),
                            autoRotates: true,
                            supportsDragNavigation: true,
                            selectionResetRevision: heroSelectionResetRevision,
                            primaryAction: { item, callbacks in
                                AnyView(
                                    Button {
                                        callbacks.restartRotation()
                                        play(item)
                                    } label: {
                                        HomeHeroActionButtonLabel(
                                            title: viewModel.heroPrimaryActionTitle(for: item),
                                            systemImage: "play.fill",
                                            fillsWidth: true
                                        )
                                    }
                                    .homeHeroNativeButtonStyle()
                                    .pointerStyle(.link)
                                    .overlay {
                                        if let progress = item.posterProgress {
                                            HomeHeroResumeProgress(progress: progress)
                                        }
                                    }
                                    .frame(
                                        maxWidth: 300,
                                        alignment: .leading
                                    )
                                    .accessibilityValue(item.posterProgress.map {
                                        "\(Int((min(1, max(0, $0)) * 100).rounded())) percent watched"
                                    } ?? "")
                                    .simultaneousGesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { _ in callbacks.pauseRotation() }
                                    )
                                    .contextMenu {
                                        HomeItemContextMenu(
                                            item: item,
                                            detailsLabel: heroDetailsLabel(for: item),
                                            onMarkWatched: {
                                                Task { await viewModel.setWatched(true, for: item) }
                                            },
                                            onMarkUnwatched: {
                                                Task { await viewModel.setWatched(false, for: item) }
                                            },
                                            onSelectRoute: { route in
                                                path.append(route)
                                            },
                                            onRemoveFromContinueWatching: {
                                                Task { await viewModel.removeFromContinueWatching(item) }
                                            }
                                        )
                                    }
                                    .accessibilityAddTraits(.isButton)
                                )
                            },
                            detailsAction: { item in
                                path.append(AppNavigationRoute.destination(for: item))
                            }
                        )
                        .modifier(HomeViewportFrame())
                    }

                    LazyVStack(alignment: .leading, spacing: 24) {
                        ServerOutageNote(offlineServerNames: offlineServerNames)
                            .padding(.horizontal, 20)

                        if showsLiveTV, let lineup = liveTVViewModel.lineup, !lineup.channels.isEmpty {
                            LiveTVHomeShelf(viewModel: liveTVViewModel, play: playLiveTV)
                                .modifier(HomeLibraryBay())
                        }

                        ForEach(viewModel.hubs) { hub in
                            hubSection(hub)
                        }

                        ForEach(viewModel.personalizedShelves) { shelf in
                            personalizedSection(shelf)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background { HomeDeckBackground().ignoresSafeArea() }
        .task(id: showsLiveTV) {
            guard showsLiveTV else { return }
            await liveTVViewModel.load(force: true)
        }
    }

    @ViewBuilder
    private func hubSection(_ hub: PlexHub) -> some View {
        let items = viewModel.inlineItems(
            in: hub,
            maxRecentlyAddedItems: recentlyAddedInlineItemLimit
        )

        if !items.isEmpty {
            let isVideoHub = viewModel.isVideoHub(hub)

            PlexItemPosterCarouselSection(
                title: hub.title,
                items: items,
                posterWidth: isVideoHub ? DuskPosterMetrics.videoCarouselWidth : 130,
                imageAspectRatio: isVideoHub ? 16.0 / 9.0 : 2.0 / 3.0,
                showAllRoute: viewModel.shouldShowAll(
                    for: hub,
                    maxRecentlyAddedItems: recentlyAddedInlineItemLimit
                ) ? AppNavigationRoute.hub(hub) : nil,
                subtitle: { isVideoHub ? $0.standardPosterSubtitle : $0.year.map(String.init) },
                posterURL: { item, width, height in
                    viewModel.posterURL(for: item, width: width, height: height)
                }
            ) { item in
                PlexItemContextMenuContent(
                    item: item,
                    onMarkWatched: {
                        Task { await viewModel.setWatched(true, for: item) }
                    },
                    onMarkUnwatched: {
                        Task { await viewModel.setWatched(false, for: item) }
                    }
                )
            }
            .modifier(HomeLibraryBay())
        }
    }

    @ViewBuilder
    private func personalizedSection(_ shelf: HomePersonalizedShelf) -> some View {
        if !shelf.items.isEmpty {
            PlexItemPosterCarouselSection(
                title: shelf.title,
                items: shelf.items,
                posterWidth: 130,
                showAllRoute: viewModel.showAllRoute(for: shelf),
                subtitle: { item in
                    viewModel.subtitle(for: item)
                },
                posterURL: { item, width, height in
                    viewModel.posterURL(for: item, width: width, height: height)
                }
            ) { item in
                PlexItemContextMenuContent(
                    item: item,
                    onMarkWatched: {
                        Task { await viewModel.setWatched(true, for: item) }
                    },
                    onMarkUnwatched: {
                        Task { await viewModel.setWatched(false, for: item) }
                    }
                )
            }
            .modifier(HomeLibraryBay())
        }
    }

    private func heroLayout(for size: CGSize) -> HomeCinematicHeroLayout {
        var layout = HomeCinematicHeroLayout.desktop
        if size.width < 800 || size.height < 800 {
            layout.titleFontSize = 36
            layout.episodeTitleFont = .title3.weight(.semibold)
            layout.summaryLineLimit = 1
            layout.contentHorizontalPadding = 24
            layout.contentTopPadding = 52
            layout.contentBottomPaddingWithPager = 52
            layout.titleBlockSpacingMovie = 10
            layout.titleBlockSpacingOther = 8
        }
        return layout
    }

    private func heroDetailsLabel(for item: PlexItem) -> String {
        switch item.type {
        case .episode:
            return "Go to Episode"
        case .season:
            return "Go to Season"
        case .show:
            return "Go to Show"
        case .movie:
            return "Go to Movie"
        default:
            return "View Details"
        }
    }
}
