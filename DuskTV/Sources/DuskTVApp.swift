import SwiftUI

@main
struct DuskTVApp: App {
    @State private var model = TVAppModel()

    var body: some Scene {
        WindowGroup { TVRootView(model: model).preferredColorScheme(.dark) }
    }
}

private struct TVServerCatalog: Sendable {
    let hubs: [PlexHub]
    let watching: [PlexItem]
    let failed: Bool
}

/// Account/profile lifetime and shared Plex catalog loading. Refreshes preserve
/// the mounted TV navigation shell; results never cross a profile boundary.
@MainActor
@Observable
final class TVAppModel {
    let service = PlexService()
    var pin: PlexPin?
    var busy = false
    var message: String?
    var continueWatching: [PlexItem] = []
    var hubs: [PlexHub] = []
    var serverMessages: [String] = []
    var ready = false
    var catalogRevision = 0
    private var catalogGeneration = UUID()

    var libraries: [PlexLibrary] {
        service.libraryOrder.orderedSections.filter { $0.libraryType != nil }
    }

    func start() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            if !service.isAuthenticated {
                let generated = try await service.generatePin()
                pin = generated
                for _ in 0..<150 {
                    try await Task.sleep(for: .seconds(2))
                    if let token = try await service.checkPin(generated.id) {
                        try Task.checkCancellation()
                        service.setAuthToken(token)
                        pin = nil
                        break
                    }
                }
                guard service.isAuthenticated else {
                    message = "This code expired. Choose Retry for a new code."
                    return
                }
            }
            try await service.bootstrapHomeSession()
            if service.isSessionReady { try await loadCatalog() }
        } catch is CancellationError {
        } catch { message = "Could not finish connecting to Plex. Check your network and choose Retry." }
    }

    func selectProfile(_ user: PlexHomeUser, pin: String) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await service.switchHomeUser(user, pin: pin.nilIfEmpty, remember: true)
            clearCatalog()
            try await loadCatalog()
        } catch { message = "Could not open that profile. Check its PIN and try again." }
    }

    func refresh() async {
        guard !busy, service.isSessionReady else { return }
        busy = true
        message = nil
        defer { busy = false }
        do { try await loadCatalog() }
        catch is CancellationError {
        } catch { message = "Could not refresh Plex. Working libraries remain available; try again." }
    }

    private func loadCatalog() async throws {
        let generation = UUID()
        catalogGeneration = generation
        let session = service.serverSessionToken
        _ = try await service.connectAllServers()
        try Task.checkCancellation()
        guard catalogGeneration == generation, session == service.serverSessionToken else { return }
        ready = true
        async let orderedLibraries = service.ensureLibraryOrderLoaded(force: true)
        var results: [Int: TVServerCatalog] = [:]
        for await result in service.streamAcrossServers({ service, id in
            async let hubs = try? service.getHubs(serverID: id)
            async let watching = try? service.getContinueWatching(serverID: id)
            let values = await (hubs, watching)
            return TVServerCatalog(hubs: values.0 ?? [], watching: values.1 ?? [],
                failed: values.0 == nil && values.1 == nil)
        }) {
            guard !Task.isCancelled, catalogGeneration == generation,
                  session == service.serverSessionToken else { return }
            results[result.rank] = result.value
            let lists = results.keys.sorted().compactMap { results[$0] }
            let mergedWatching = ContinueWatchingMerge.merge(lists.map(\.watching))
            let mergedHubs = HubMerge.merge(lists.map(\.hubs))
            continueWatching = mergedWatching.items.filter(\.isTVBrowsable)
            hubs = mergedHubs.hubs.map { $0.replacingItems($0.items.filter(\.isTVBrowsable)) }.filter {
                !$0.items.isEmpty && !($0.hubIdentifier ?? "").lowercased().contains("continuewatching")
            }
            service.registerAlternates(mergedWatching.alternates)
            service.registerAlternates(mergedHubs.alternates)
        }
        do { _ = try await orderedLibraries }
        catch { message = "Some libraries could not be loaded. Refresh to retry." }
        guard catalogGeneration == generation, session == service.serverSessionToken else { return }
        serverMessages = service.pool.priorityOrderedIdentifiers.compactMap { id in
            service.pool.connection(for: id) == nil && service.serverPriority.isEnabled(id)
                ? "\(service.pool.displayName(for: id)) is unavailable." : nil
        }
        if results.values.contains(where: \.failed) {
            serverMessages.append("Some connected servers could not load their Home shelves.")
        }
        catalogRevision += 1
    }

    private func clearCatalog() {
        catalogGeneration = UUID()
        continueWatching = []
        hubs = []
        serverMessages = []
        ready = false
        catalogRevision += 1
    }

    func signOut() {
        catalogGeneration = UUID()
        service.signOut()
        clearCatalog()
        pin = nil
        message = nil
    }
}
