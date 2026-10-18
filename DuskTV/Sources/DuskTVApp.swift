import SwiftUI

@main
struct DuskTVApp: App {
    @State private var model = TVAppModel()

    var body: some Scene {
        WindowGroup {
            TVRootView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}

/// Prototype UI state. Plex credentials, discovery and server identity remain
/// owned by the same PlexService used on Mac.
@MainActor
@Observable
final class TVAppModel {
    let service = PlexService()
    var pin: PlexPin?
    var busy = false
    var message: String?
    var libraries: [PlexLibrary] = []
    var continueWatching: [PlexItem] = []
    var serverMessages: [String] = []
    var ready = false

    func start() async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            if !service.isAuthenticated {
                let generated = try await service.generatePin()
                pin = generated
                // A PIN expires; bound polling so a remote Retry can renew it.
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
            if service.isSessionReady { try await loadLibraries() }
        } catch is CancellationError {
        } catch {
            message = "Could not finish connecting to Plex. Check your network and choose Retry."
        }
    }

    func selectProfile(_ user: PlexHomeUser, pin: String) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await service.switchHomeUser(user, pin: pin.nilIfEmpty, remember: true)
            try await loadLibraries()
        } catch {
            message = "Could not open that profile. Check its PIN and try again."
        }
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        message = nil
        do { try await loadLibraries() }
        catch { message = "Could not connect to your Plex servers. Check the network and retry." }
    }

    private func loadLibraries() async throws {
        ready = false
        libraries = []
        continueWatching = []
        serverMessages = []
        _ = try await service.connectAllServers()
        try Task.checkCancellation()
        // Failures are kept per server; one outage does not hide other libraries.
        for serverID in service.pool.priorityOrderedIdentifiers {
            guard let connection = service.pool.connection(for: serverID) else {
                serverMessages.append("A Plex server is unavailable. Refresh to retry.")
                continue
            }
            do {
                let sections = try await service.getLibraries(serverID: serverID)
                libraries += sections.filter { $0.libraryType != nil }
                continueWatching += (try? await service.getContinueWatching(serverID: serverID)) ?? []
            } catch {
                serverMessages.append("\(connection.name): libraries unavailable. Refresh to retry.")
            }
        }
        ready = true
    }

    func signOut() {
        service.signOut()
        libraries = []
        continueWatching = []
        serverMessages = []
        ready = false
        pin = nil
        message = nil
    }
}
