import SwiftUI

@main
struct CineramaTVApp: App {
    @State private var model = TVAppModel()

    var body: some Scene {
        WindowGroup {
            TVRootView(model: model)
                .background { TVDeckBackground().ignoresSafeArea() }
                .preferredColorScheme(.dark)
        }
    }
}

/// Account/profile lifetime and shared Plex catalog loading. Refreshes preserve
/// the mounted TV navigation shell; results never cross a profile boundary.
@MainActor
@Observable
final class TVAppModel {
    let service: PlexService
    let home: HomeViewModel
    var personalizedShelvesEnabled: Bool {
        didSet {
            UserDefaults.standard.set(personalizedShelvesEnabled, forKey: "personalizedShelvesEnabled")
            home.setPersonalizedShelvesEnabled(personalizedShelvesEnabled)
        }
    }
    var pin: PlexPin?
    var busy = false
    var message: String?
    var ready = false
    private var catalogGeneration = UUID()

    init() {
        let service = PlexService()
        self.service = service
        let enabled = UserDefaults.standard.object(forKey: "personalizedShelvesEnabled") as? Bool ?? true
        personalizedShelvesEnabled = enabled
        home = HomeViewModel(plexService: service, personalizedShelvesEnabled: enabled)
    }

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
        home.cancelLoads()
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

    /// Playback dismissal must supersede an in-flight Home load, not be
    /// skipped by the server-discovery busy guard or show stale progress.
    func refreshHome() async {
        guard service.isSessionReady else { return }
        message = nil
        await home.load(maxRecentlyAddedItems: 15)
    }

    private func loadCatalog() async throws {
        let generation = UUID()
        catalogGeneration = generation
        let session = service.serverSessionToken
        _ = try await service.connectAllServers()
        try Task.checkCancellation()
        guard catalogGeneration == generation, session == service.serverSessionToken else { return }
        ready = true
        await home.load(maxRecentlyAddedItems: 15)
        guard catalogGeneration == generation, session == service.serverSessionToken else { return }
    }

    private func clearCatalog() {
        catalogGeneration = UUID()
        home.cancelLoads(clearContent: true)
        ready = false
    }

    func signOut() {
        catalogGeneration = UUID()
        home.cancelLoads(clearContent: true)
        service.signOut()
        clearCatalog()
        pin = nil
        message = nil
    }
}
