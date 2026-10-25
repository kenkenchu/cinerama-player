import SwiftUI

private enum TVHomeRoute: Hashable {
    case item(PlexItemID)
    case hub(PlexHub)
    case genre(PlexLibrary, LibraryGenreOption)
}

struct TVHomeView: View {
    @Bindable var model: TVAppModel
    let isSelected: Bool
    let onSearch: () -> Void
    @State private var path: [TVHomeRoute] = []
    @State private var playback = TVHomePlaybackModel()
    @State private var heroReset = 0
    @State private var hasAppeared = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if (model.busy || model.home.isLoading) && !model.home.hasLoadedContent {
                    ProgressView("Loading Home…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 38) {
                            header
                            if !model.home.heroItems().isEmpty {
                                TVHomeHero(service: model.service, home: model.home,
                                    items: model.home.heroItems(), isActive: isSelected && path.isEmpty && playback.presentation == nil,
                                    selectionReset: heroReset, isPreparing: playback.isPreparing,
                                    play: { item in Task { await playback.play(item, service: model.service) } },
                                    details: { path.append(.item($0.id)) },
                                    navigate: { path.append(.item($0)) })
                                    .padding(.horizontal, 60)
                            }
                            if let message = model.message { Text(message).padding(.horizontal, 60) }
                            availabilityNote
                            if model.home.error != nil && model.home.hasLoadedContent {
                                Text("A Home update could not be completed. Refresh to retry.")
                                    .foregroundStyle(.secondary).padding(.horizontal, 60)
                            }
                            if model.home.error != nil && !model.home.hasLoadedContent {
                                ContentUnavailableView {
                                    Label("Home is unavailable", systemImage: "network.slash")
                                } description: { Text("Plex could not load your Home content. Refresh to retry.") }
                            }
                            ForEach(model.home.hubs) { hub in
                                let items = model.home.inlineItems(in: hub, maxRecentlyAddedItems: 15).filter(\.isTVBrowsable)
                                if !items.isEmpty {
                                    shelf(title: hub.title, items: items, landscape: model.home.isVideoHub(hub),
                                        showAll: model.home.shouldShowAll(for: hub, maxRecentlyAddedItems: 15) ? .hub(hub) : nil)
                                }
                            }
                            ForEach(model.home.personalizedShelves) { personalized in
                                shelf(title: personalized.title, items: personalized.items, landscape: false,
                                    showAll: personalized.showAllLibrary.map { .genre($0, personalized.genre) })
                            }
                            if !model.home.hasLoadedContent && !model.busy && model.home.error == nil && model.service.pool.availability.isReady {
                                ContentUnavailableView("Your Home is empty", systemImage: "house",
                                    description: Text("Browse Libraries to start watching. Refresh if your server has just come online."))
                            }
                        }.padding(.bottom, 70)
                    }
                }
            }
            .background { TVDeckBackground().ignoresSafeArea() }
            .navigationTitle("")
            .navigationDestination(for: TVHomeRoute.self) { route in
                switch route {
                case .item(let id): TVMediaView(service: model.service, itemID: id)
                case .hub(let hub): TVHomeHubView(service: model.service, hub: hub,
                    home: model.home, navigate: { path.append(.item($0)) })
                case .genre(let library, let genre): TVHomeGenreView(service: model.service,
                    library: library, genre: genre, home: model.home,
                    navigate: { path.append(.item($0)) })
                }
            }
        }
        .fullScreenCover(item: $playback.presentation, onDismiss: {
            Task {
                let session = model.service.serverSessionToken
                defer { playback.awaitsFinalization = false }
                await playback.lastPlayback?.finish()
                guard session == model.service.serverSessionToken else { return }
                NotificationCenter.default.post(name: .tvCatalogNeedsRefresh, object: nil)
            }
        }) { session in TVPlayerScreen(playback: session.playback) }
        .alert("Unable to Play", isPresented: Binding(get: { playback.message != nil },
            set: { if !$0 { playback.message = nil } })) {
            Button("OK") { playback.message = nil }
        } message: { Text(playback.message ?? "") }
        .onAppear {
            if hasAppeared && !playback.awaitsFinalization {
                Task { await model.refreshHome() }
            }
            hasAppeared = true
        }
        .onDisappear { playback.cancelPreparation() }
        .onChange(of: isSelected) { _, selected in
            if selected {
                heroReset += 1
                Task { await model.refresh() }
            } else { playback.cancelPreparation() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && isSelected && path.isEmpty && !playback.awaitsFinalization {
                heroReset += 1
                Task { await model.refresh() }
            } else if phase != .active { playback.cancelPreparation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tvCatalogNeedsRefresh)) { _ in heroReset += 1 }
        .onChange(of: model.service.serverContentRevision) { _, _ in
            guard !model.busy, model.service.isSessionReady else { return }
            Task { await model.home.load(maxRecentlyAddedItems: 15) }
        }
    }

    @ViewBuilder
    private var availabilityNote: some View {
        switch model.service.pool.availability {
        case .ready(let names):
            if !names.isEmpty {
                Text("Unavailable servers: " + names.joined(separator: ", "))
                    .foregroundStyle(.secondary).padding(.horizontal, 60)
            }
        case .allDisabled:
            Text("Your Plex servers are disabled. Enable a server in Settings.")
                .foregroundStyle(.secondary).padding(.horizontal, 60)
        case .unreachable:
            Text("Your Plex servers could not be reached. Check the network and refresh.")
                .foregroundStyle(.secondary).padding(.horizontal, 60)
        case .unknown:
            if !model.busy { Text("No Plex servers are available for this profile.").padding(.horizontal, 60) }
        case .connecting:
            Text("Connecting to Plex servers…").foregroundStyle(.secondary).padding(.horizontal, 60)
        }
    }

    private var header: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CINERAMA / SCREENING DECK")
                    .font(.system(.title3, design: .monospaced, weight: .semibold)).tracking(3)
                Text(model.service.activeHomeUser?.displayName ?? "Your Plex libraries")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TVDeckRule()
            Text("\(model.home.heroItems().count) FEATURED")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            if model.busy { ProgressView() }
            Button(action: onSearch) { Label("Search", systemImage: "magnifyingglass") }
                .modifier(TVDeckActionStyle())
            Button { Task { await model.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }.modifier(TVDeckActionStyle()).disabled(model.busy)
        }.padding(.horizontal, 60).padding(.top, 35)
    }

    private func shelf(title: String, items: [PlexItem], landscape: Bool, showAll: TVHomeRoute?) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(title).font(.title2.bold())
                TVDeckRule().padding(.horizontal, 20)
                if let showAll {
                    NavigationLink("Show All", value: showAll).modifier(TVDeckActionStyle())
                }
            }.padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 38) {
                    ForEach(items) { item in
                        TVMediaCard(service: model.service, item: item, landscape: landscape,
                            select: { path.append(.item(item.id)) })
                            .contextMenu {
                                TVHomeItemActions(item: item, home: model.home,
                                    navigate: { path.append(.item($0)) })
                            }
                    }
                }.padding(.horizontal, 60).padding(.vertical, 24)
            }.scrollClipDisabled()
        }
        .modifier(TVDeckBay())
    }
}

/// Long-press actions preserve Plex identity and operate on known alternate
/// copies using the same domain methods as Mac Home.
struct TVHomeItemActions: View {
    let item: PlexItem
    let home: HomeViewModel
    let navigate: (PlexItemID) -> Void
    var canRemove = false
    var setWatched: ((Bool) -> Void)?

    var body: some View {
        if item.canMarkWatchedFromContextMenu {
            Button("Mark Watched", systemImage: "eye") {
                if let setWatched { setWatched(true) }
                else { Task { await home.setWatched(true, for: item) } }
            }
        }
        if item.canMarkUnwatchedFromContextMenu {
            Button("Mark Unwatched", systemImage: "eye.slash") {
                if let setWatched { setWatched(false) }
                else { Task { await home.setWatched(false, for: item) } }
            }
        }
        if canRemove {
            Button("Remove from Continue Watching", systemImage: "minus.circle") {
                Task { await home.removeFromContinueWatching(item) }
            }
        }
        Button("View Details", systemImage: "info.circle") { navigate(item.id) }
        if item.type == .episode, let season = item.parentRatingKey {
            Button("Go to Season", systemImage: "rectangle.stack") {
                navigate(PlexItemID(serverID: item.serverID, ratingKey: season))
            }
        }
        if let show = item.type == .episode ? item.grandparentRatingKey
            : (item.type == .season ? item.parentRatingKey : nil) {
            Button("Go to Show", systemImage: "tv") {
                navigate(PlexItemID(serverID: item.serverID, ratingKey: show))
            }
        }
    }
}
