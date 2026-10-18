import SwiftUI

struct TVRootView: View {
    @Bindable var model: TVAppModel
    @State private var profile: PlexHomeUser?
    @State private var profilePIN = ""

    var body: some View {
        NavigationStack {
            Group {
                if model.service.needsHomeUserSelection {
                    profilePicker
                } else if model.ready {
                    libraryList
                } else {
                    connectionView
                }
            }
            .navigationTitle("Dusk Prototype")
        }
        .task { await model.start() }
    }

    private var connectionView: some View {
        VStack(spacing: 30) {
            Text("Plex on Apple TV").font(.largeTitle)
            if let pin = model.pin {
                Text("On your phone or computer, open plex.tv/link and enter:")
                Text(pin.code).font(.system(size: 72, weight: .bold, design: .monospaced))
                Text("Sign in to the Plex account that owns or can access your libraries.")
                    .foregroundStyle(.secondary)
            }
            if model.busy { ProgressView("Connecting…") }
            if let message = model.message { Text(message).multilineTextAlignment(.center) }
            if !model.busy {
                Button("Retry") { Task { await model.start() } }
                if model.service.isAuthenticated {
                    Button("Sign Out") { model.signOut(); Task { await model.start() } }
                }
            }
        }
        .padding(70)
    }

    private var profilePicker: some View {
        List {
            Section("Choose your Plex profile") {
                ForEach(model.service.homeUsers) { user in
                    Button(user.displayName + (user.isProtected ? " 🔒" : "")) {
                        profilePIN = ""
                        if user.isProtected { profile = user }
                        else { Task { await model.selectProfile(user, pin: "") } }
                    }
                    .disabled(model.busy)
                }
            }
            if model.busy { ProgressView("Opening profile…") }
            if let message = model.message { Text(message) }
            Button("Sign Out") { model.signOut(); Task { await model.start() } }
                .disabled(model.busy)
        }
        .sheet(item: $profile) { user in
            VStack(spacing: 30) {
                Text(user.displayName).font(.title)
                SecureField("Plex Home PIN", text: $profilePIN).keyboardType(.numberPad)
                Button("Continue") {
                    let enteredPIN = profilePIN
                    profilePIN = ""
                    profile = nil
                    Task { await model.selectProfile(user, pin: enteredPIN) }
                }
                Button("Cancel") { profilePIN = ""; profile = nil }
            }.padding(90)
        }
    }

    private var libraryList: some View {
        List {
            Section {
                Text("HD feasibility prototype · Original quality · No server re-encoding")
                    .foregroundStyle(.secondary)
                if model.busy { ProgressView("Refreshing…") }
                if let message = model.message { Text(message) }
                ForEach(Array(model.serverMessages.enumerated()), id: \.offset) { _, message in
                    Text(message).foregroundStyle(.secondary)
                }
            }
            if !model.continueWatching.isEmpty {
                Section("Continue Watching") {
                    ForEach(model.continueWatching) { item in
                        NavigationLink {
                            TVMediaView(service: model.service, itemID: item.id)
                        } label: {
                            TVItemLabel(title: item.title, subtitle: item.grandparentTitle)
                        }
                    }
                }
            }
            Section("Libraries") {
                ForEach(model.libraries) { library in
                    NavigationLink {
                        TVLibraryView(service: model.service, library: library)
                    } label: {
                        TVItemLabel(title: library.title,
                            subtitle: model.service.pool.connection(for: library.serverID)?.name)
                    }
                }
                if model.libraries.isEmpty { Text("No video libraries are available. Check Plex access and Local Network permission.") }
            }
            Section {
                Button("Refresh Servers") { Task { await model.refresh() } }.disabled(model.busy)
                Button("Sign Out") { model.signOut(); Task { await model.start() } }.disabled(model.busy)
            }
        }
    }
}

struct TVItemLabel: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

@MainActor
@Observable
final class TVLibraryModel {
    var items: [PlexItem] = []
    var busy = false
    var message: String?
    var hasMore = true

    func load(service: PlexService, library: PlexLibrary) async {
        guard !busy, hasMore else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let page = try await service.getLibraryItems(sectionId: library.key,
                start: items.count, size: 50, sort: "titleSort", serverID: library.serverID)
            try Task.checkCancellation()
            items += page
            hasMore = page.count == 50
        } catch is CancellationError {
        } catch { message = "Could not load this library. Try again." }
    }
}

struct TVLibraryView: View {
    let service: PlexService
    let library: PlexLibrary
    @State private var model = TVLibraryModel()

    var body: some View {
        List {
            ForEach(model.items) { item in
                NavigationLink {
                    TVMediaView(service: service, itemID: item.id)
                } label: {
                    TVItemLabel(title: item.title, subtitle: item.year.map(String.init))
                }
            }
            if model.busy { ProgressView("Loading…") }
            if let message = model.message { Text(message) }
            if model.hasMore && !model.busy {
                Button(model.message == nil ? "Load More" : "Retry") {
                    Task { await model.load(service: service, library: library) }
                }
            }
            if !model.hasMore && model.items.isEmpty { Text("This library is empty.") }
        }
        .navigationTitle(library.title)
        .task { if model.items.isEmpty { await model.load(service: service, library: library) } }
    }
}
