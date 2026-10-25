import SwiftUI

/// Home Show All uses the same merged, expanded source data as Mac Home.
struct TVHomeHubView: View {
    let service: PlexService
    let home: HomeViewModel
    let navigate: (PlexItemID) -> Void
    @State private var model: HomeHubItemsViewModel

    init(service: PlexService, hub: PlexHub, home: HomeViewModel, navigate: @escaping (PlexItemID) -> Void) {
        self.service = service
        self.home = home
        self.navigate = navigate
        _model = State(initialValue: HomeHubItemsViewModel(hub: hub, plexService: service))
    }

    var body: some View {
        ScrollView {
            if model.isLoading && model.items.isEmpty { ProgressView("Loading…").padding(60) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: model.items.isAllClips ? 360 : 240), spacing: 35)], spacing: 45) {
                ForEach(model.items.filter(\.isTVBrowsable)) { item in
                    TVMediaCard(service: service, item: item, landscape: model.items.isAllClips,
                        select: { navigate(item.id) })
                        .contextMenu {
                            TVHomeItemActions(item: item, home: home, navigate: navigate,
                                setWatched: { watched in Task { await model.setWatched(watched, for: item) } })
                        }
                }
            }.padding(60)
            if model.items.isEmpty && !model.isLoading {
                ContentUnavailableView("No items available", systemImage: "film")
                Button("Retry") { Task { await model.reloadItems() } }
            }
            if model.error != nil { Text("This row could not be refreshed. Try again.").padding() }
        }
        .background { TVDeckBackground().ignoresSafeArea() }
        .navigationTitle(model.navigationTitle)
        .task { await model.reloadItems() }
    }
}

/// Personalized Show All follows the same single-library, locally matched
/// genre route as Mac; do not treat a genre's display title as a Plex filter ID.
struct TVHomeGenreView: View {
    let service: PlexService
    let home: HomeViewModel
    let navigate: (PlexItemID) -> Void
    @State private var model: LibraryItemsViewModel

    init(service: PlexService, library: PlexLibrary, genre: LibraryGenreOption,
         home: HomeViewModel, navigate: @escaping (PlexItemID) -> Void) {
        self.service = service
        self.home = home
        self.navigate = navigate
        _model = State(initialValue: LibraryItemsViewModel(library: library, plexService: service,
            initialGenre: genre, preferLocalGenreFiltering: true))
    }

    var body: some View {
        ScrollView {
            if model.isLoading { ProgressView("Loading…").padding(60) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 35)], spacing: 45) {
                ForEach(model.items.filter(\.isTVBrowsable)) { item in
                    TVMediaCard(service: service, item: item, select: { navigate(item.id) })
                        .contextMenu {
                            TVHomeItemActions(item: item, home: home, navigate: navigate,
                                setWatched: { watched in Task { await model.setWatched(watched, for: item) } })
                        }
                }
            }.padding(60)
            if model.isLoadingMore { ProgressView("Loading more…") }
            if model.hasMoreItems && !model.isLoading && !model.isLoadingMore, let last = model.items.last {
                Button("Load More") { Task { await model.loadMoreIfNeeded(currentItem: last) } }
            }
            if model.items.isEmpty && !model.isLoading {
                ContentUnavailableView("No matching titles", systemImage: "film")
                Button("Retry") { Task { await model.reloadItems() } }
            }
            if model.error != nil { Text("This genre could not be refreshed. Try again.").padding() }
        }
        .background { TVDeckBackground().ignoresSafeArea() }
        .navigationTitle(model.navigationTitle)
        .task {
            if model.items.isEmpty { await model.loadItems() }
            else { await model.reloadItems() }
        }
    }
}
