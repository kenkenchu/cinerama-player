import SwiftUI

struct TVCatalogShell: View {
    @Bindable var model: TVAppModel
    var body: some View {
        TabView {
            NavigationStack { TVHomeView(model: model) }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack {
                List {
                    ForEach(model.libraries) { library in
                        NavigationLink {
                            TVLibraryView(service: model.service, library: library)
                        } label: {
                            Label {
                                TVItemLabel(title: library.title,
                                    subtitle: model.service.pool.displayName(for: library.serverID ?? ""))
                            } icon: { Image(systemName: library.libraryType?.systemImage ?? "film") }
                        }
                    }
                    if model.libraries.isEmpty {
                        Text(model.busy ? "Loading libraries…" : "No video libraries are available.")
                    }
                }.navigationTitle("Libraries")
            }.tabItem { Label("Libraries", systemImage: "rectangle.stack") }
            NavigationStack { TVSearchView(service: model.service) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack { TVSettingsView(model: model) }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

struct TVHomeView: View {
    @Bindable var model: TVAppModel
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 42) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dusk").font(.largeTitle.bold())
                        Text(model.service.activeHomeUser?.displayName ?? "Your Plex libraries")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.busy { ProgressView() }
                    Button { Task { await model.refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }.disabled(model.busy)
                }.padding(.horizontal, 60)
                if let message = model.message { Text(message).padding(.horizontal, 60) }
                ForEach(Array(model.serverMessages.enumerated()), id: \.offset) { _, message in
                    Text(message).foregroundStyle(.secondary).padding(.horizontal, 60)
                }
                if !model.continueWatching.isEmpty {
                    TVMediaShelf(service: model.service, title: "Continue Watching", items: model.continueWatching)
                }
                ForEach(model.hubs) { hub in
                    VStack(alignment: .leading) {
                        TVMediaShelf(service: model.service, title: hub.title, items: hub.items)
                        if hub.more == true || (hub.size ?? 0) > hub.items.count {
                            NavigationLink("Show All · \(hub.title)") {
                                TVHubView(service: model.service, hub: hub)
                            }.padding(.horizontal, 60)
                        }
                    }
                }
                if model.hubs.isEmpty && model.continueWatching.isEmpty && !model.busy {
                    ContentUnavailableView("Your library is ready", systemImage: "film",
                        description: Text("Open Libraries to browse your movies and shows."))
                }
            }.padding(.vertical, 40)
        }
        .navigationTitle("Home")
    }
}

@MainActor
@Observable
final class TVSearchModel {
    var groups: [PlexSearchResult] = []
    var loading = false
    var message: String?
    private var generation = UUID()

    func search(_ query: String, service: PlexService) async {
        let attempt = UUID()
        generation = attempt
        groups = []
        message = nil
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { loading = false; return }
        loading = true
        defer { if generation == attempt { loading = false } }
        do { try await Task.sleep(for: .milliseconds(350)) }
        catch { return }
        let identity = service.serverSessionToken
        var lists: [Int: [PlexSearchResult]] = [:]
        var successes = 0
        for await result in service.streamSearch(query: query) {
            guard !Task.isCancelled, generation == attempt, identity == service.serverSessionToken else { return }
            if case .success(let results) = result.value {
                lists[result.rank] = results
                successes += 1
            }
            let merged = SearchMerge.merge(lists.keys.sorted().compactMap { lists[$0] })
            groups = merged.groups.map { group in
                PlexSearchResult(title: group.title, type: group.type, items: group.items.filter {
                    $0.isTVBrowsable
                })
            }.filter { !$0.items.isEmpty }
            service.registerAlternates(merged.alternates)
        }
        if successes == 0 { message = "No servers could complete the search. Refresh your servers in Settings." }
    }
}

struct TVSearchView: View {
    let service: PlexService
    @State private var query = ""
    @State private var model = TVSearchModel()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 40) {
                if model.loading { ProgressView("Searching…").padding(60) }
                if let message = model.message { Text(message).padding(60) }
                ForEach(model.groups) { group in
                    TVMediaShelf(service: service, title: group.title, items: group.items)
                }
                if !model.loading && model.groups.isEmpty && model.message == nil {
                    ContentUnavailableView(query.isEmpty ? "Search your libraries" : "No results",
                        systemImage: "magnifyingglass", description: Text("Find movies, shows and episodes across your connected Plex servers."))
                }
            }.padding(.vertical, 35)
        }
        .searchable(text: $query, prompt: "Movies, shows and episodes")
        .navigationTitle("Search")
        .task(id: query) { await model.search(query, service: service) }
    }
}

@MainActor
@Observable
final class TVHubModel {
    var items: [PlexItem] = []
    var loading = false
    var limit = 50
    var hasMore = true
    func load(service: PlexService, hub: PlexHub) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let result = await service.mergedHubItems(for: hub, size: limit)
        guard !Task.isCancelled else { return }
        let previousCount = items.count
        items = result.items.filter(\.isTVBrowsable)
        service.registerAlternates(result.alternates)
        hasMore = hub.sources.contains { ($0.size ?? 0) > limit }
            || (result.items.count > previousCount && (hub.more == true || result.items.count >= limit))
        limit += 50
    }
}

struct TVHubView: View {
    let service: PlexService
    let hub: PlexHub
    @State private var model = TVHubModel()
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 35)], spacing: 45) {
                ForEach(model.items) { TVMediaCard(service: service, item: $0) }
            }.padding(60)
            if model.loading { ProgressView() }
            if model.hasMore && !model.loading {
                Button("Load More") { Task { await model.load(service: service, hub: hub) } }
            }
            if model.items.isEmpty && !model.loading { Text("No items could be loaded. Go back and refresh to retry.") }
        }
        .navigationTitle(hub.title)
        .task { if model.items.isEmpty { await model.load(service: service, hub: hub) } }
    }
}

struct TVSettingsView: View {
    @Bindable var model: TVAppModel
    @State private var confirmingSignOut = false
    var body: some View {
        Form {
            Section("Plex account") {
                LabeledContent("Profile", value: model.service.activeHomeUser?.displayName ?? "Plex account")
                if model.service.hasPlexHome {
                    Button("Switch Profile") { model.service.requestHomeUserSelection() }.disabled(model.busy)
                }
                Button("Refresh Servers") { Task { await model.refresh() } }.disabled(model.busy)
                Button("Sign Out", role: .destructive) { confirmingSignOut = true }.disabled(model.busy)
            }
            Section("Servers") {
                ForEach(model.service.pool.priorityOrderedIdentifiers, id: \.self) { id in
                    LabeledContent(model.service.pool.displayName(for: id),
                        value: model.service.pool.connection(for: id) == nil ? "Unavailable" : "Connected")
                }
            }
            Section("Playback") {
                LabeledContent("Quality", value: "Original")
                Text("Compatible HD SDR video plays directly or through copy-only remuxing. Server video/audio re-encoding is disabled.")
                Text("Caption appearance comes from Apple TV Settings → Accessibility → Subtitles and Captioning → Style.")
            }
            Section("About") {
                LabeledContent("Device", value: "Apple TV HD · tvOS 26+")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of Plex on this Apple TV?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive) { model.signOut(); Task { await model.start() } }
        }
    }
}
