import SwiftUI

struct SearchView: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            SearchRootContent()
                .cineramaAppNavigationDestinations()
        }
    }
}

struct SearchRootContent: View {
    @Environment(PlexService.self) private var plexService
    @Environment(SeerrService.self) private var seerrService
    @State private var viewModel: SearchViewModel?
    @State private var isSearchPresented = false

    private let searchPrompt = "Movies, Shows, Actors..."

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            if let viewModel {
                searchContent(viewModel)
            }
        }
        .navigationTitle("Search")

        .onAppear {
            if viewModel == nil {
                viewModel = SearchViewModel(
                    plexService: plexService,
                    seerrService: seerrService
                )
            }
        }
    }

    @ViewBuilder
    private func searchContent(_ vm: SearchViewModel) -> some View {
        platformResults(vm)
            .onChange(of: vm.query) {
                vm.searchDebounced()
            }
            // A server connecting or dropping changes what "search" even means,
            // so the current query is run again against the new set.
            .task(id: plexService.serverContentRevision) {
                guard vm.hasSearched else { return }
                vm.searchDebounced()
            }
    }

    @ViewBuilder
    private func platformResults(_ vm: SearchViewModel) -> some View {
        @Bindable var vm = vm

        carouselResults(vm)
            .searchable(text: $vm.query, prompt: searchPrompt)
    }
}

struct SearchToolbarLink: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .cineramaShowSearch, object: nil)
        } label: {
            Image(systemName: "magnifyingglass")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.primary)
        }
        .tint(Color.primary)
        .accessibilityLabel("Search")
    }
}

// MARK: - Shared Results

private extension SearchRootContent {
    /// Wraps the populated results with the shared loading / error / empty states
    /// so every platform reports state the same way.
    @ViewBuilder
    func searchResults<Content: View>(
        _ vm: SearchViewModel,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let availability = plexService.pool.availability

        if vm.results.isEmpty, !availability.isReady {
            // Nothing can be searched yet, and the reason is the servers.
            ServerAvailabilityStateView(availability: availability)
        } else if vm.isSearching && vm.results.isEmpty {
            FeatureLoadingView()
        } else if let error = vm.error, vm.results.isEmpty {
            FeatureErrorView(message: error) {
                vm.searchDebounced()
            }
        } else if vm.hasSearched && vm.results.isEmpty {
            FeatureEmptyStateView(
                systemImage: "film.stack",
                title: "No results found",
                message: "Try a different title, show, or actor."
            )
        } else if vm.results.isEmpty {
            FeatureEmptyStateView(
                systemImage: "magnifyingglass",
                title: "Search your Plex library",
                message: "Find movies, shows, episodes, and people."
            )
        } else {
            content()
        }
    }

    @ViewBuilder
    func carouselResults(_ vm: SearchViewModel) -> some View {
        searchResults(vm) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CineramaPosterMetrics.pageSectionSpacing) {
                    ServerOutageNote(
                        offlineServerNames: plexService.pool.availability.offlineServerNames
                    )
                    .padding(.horizontal, CineramaPosterMetrics.carouselHorizontalPadding)

                    ForEach(vm.results) { group in
                        let isVideoGroup = group.isAllClips
                        let width = isVideoGroup
                            ? CineramaPosterMetrics.videoCarouselWidth
                            : CineramaPosterMetrics.carouselPosterWidth
                        let aspectRatio = isVideoGroup ? 16.0 / 9.0 : 2.0 / 3.0

                        MediaCarousel(title: group.title) {
                            ForEach(group.items) { item in
                                PosterNavigationCard(
                                    route: item.route,
                                    imageURL: vm.imageURL(
                                        for: item,
                                        width: Int(width * 2),
                                        height: Int(width / aspectRatio * 2)
                                    ),
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    progress: item.progress,
                                    width: width,
                                    imageAspectRatio: aspectRatio,
                                    availabilityBadge: vm.availabilityBadge(for: item)
                                )
                            }
                        }
                    }
                }
                .padding(.top, CineramaPosterMetrics.pageSectionSpacing)
                .padding(.bottom, CineramaPosterMetrics.pageBottomPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }
}
