import AppKit
import SwiftUI

private enum MacDestination: String, CaseIterable, Identifiable {
    case home = "Home", movies = "Movies", shows = "TV Shows", videos = "Videos"
    case liveTV = "Live TV", search = "Search", downloads = "Downloads", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .home: "house"
        case .movies: "film"
        case .shows: "tv"
        case .videos: "play.rectangle"
        case .liveTV: "dot.radiowaves.left.and.right"
        case .search: "magnifyingglass"
        case .downloads: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }
}

struct MainTabView: View {
    @Environment(PlexService.self) private var plex
    @Environment(PlaybackCoordinator.self) private var playback
    @State private var playbackIsDetached = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selection: MacDestination? = .home
    @State private var paths: [MacDestination: NavigationPath] = [:]
    @State private var libraries: LibrariesViewModel?
    @State private var liveTV: LiveTVViewModel?

    var body: some View {
        ZStack {
            navigationShell
                // Keep pushed catalog destinations alive, but never above playback.
                .opacity(playback.showPlayer && !playbackIsDetached ? 0 : 1)
                .disabled(playback.showPlayer && !playbackIsDetached)
                .allowsHitTesting(!playback.showPlayer || playbackIsDetached)
                .accessibilityHidden(playback.showPlayer && !playbackIsDetached)
                .toolbarVisibility(playback.showPlayer && !playbackIsDetached ? .hidden : .automatic, for: .windowToolbar)

            if playback.showPlayer {
                MacPlaybackHost(playback: playback, isDetached: $playbackIsDetached)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(!playbackIsDetached)
                    .zIndex(1)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color.duskBackground)
        .task(id: plex.serverContentRevision) {
            if libraries == nil { libraries = LibrariesViewModel(plexService: plex) }
            if liveTV == nil { liveTV = LiveTVViewModel(plexService: plex) }
            await libraries?.loadLibraries()
            await liveTV?.discover()
        }
        .onChange(of: playback.showPlayer) { _, shown in
            if !shown {
                playbackIsDetached = false
                playback.onPlayerDismissed()
            }
        }
        .onDisappear {
            if playback.showPlayer {
                playback.showPlayer = false
                playback.onPlayerDismissed()
            }
        }
        .onChange(of: selection) { _, _ in
            if playback.showPlayer { playback.showPlayer = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .duskShowSearch)) { _ in
            selection = .search
        }
    }

    /// Playback is a sibling above this shell, never a replacement for a
    /// NavigationStack root that may have a pushed detail destination.
    private var navigationShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(MacDestination.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Dusk")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            if let libraries, let liveTV {
                destination(selection ?? .home, libraries: libraries, liveTV: liveTV)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func path(_ item: MacDestination) -> Binding<NavigationPath> {
        Binding(get: { paths[item] ?? NavigationPath() }, set: { paths[item] = $0 })
    }

    @ViewBuilder private func destination(_ item: MacDestination, libraries: LibrariesViewModel, liveTV: LiveTVViewModel) -> some View {
        switch item {
        case .home: HomeView(path: path(.home), isSelected: true, liveTVViewModel: liveTV)
        case .movies: LibrariesView(libraryType: .movie, viewModel: libraries, path: path(.movies))
        case .shows: LibrariesView(libraryType: .show, viewModel: libraries, path: path(.shows))
        case .videos: LibrariesView(libraryType: .video, viewModel: libraries, path: path(.videos))
        case .search: SearchView(path: path(.search))
        case .downloads: DownloadsView(path: path(.downloads))
        case .liveTV: LiveTVView(viewModel: liveTV, path: path(.liveTV))
        case .settings: SettingsView(path: path(.settings))
        }
    }
}

struct DuskMacCommands: Commands {
    var body: some Commands {
        SidebarCommands()
        CommandGroup(after: .textEditing) {
            Button("Search Library") { NotificationCenter.default.post(name: .duskShowSearch, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let duskShowSearch = Notification.Name("DuskShowSearch")
}

/// Reparents one hosting view so fullscreen never recreates the player session
/// or changes the catalog window's fullscreen state.
private struct MacPlaybackHost: NSViewRepresentable {
    let playback: PlaybackCoordinator
    @Binding var isDetached: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(playback: playback, detached: $isDetached)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.container = container
        context.coordinator.attachPlayer(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        let playback: PlaybackCoordinator
        weak var container: NSView?
        private var hostingView: NSHostingView<AnyView>?
        private var fullscreenWindow: NSWindow?
        private var transitioning = false
        private let detached: Binding<Bool>

        init(playback: PlaybackCoordinator, detached: Binding<Bool>) {
            self.detached = detached
            self.playback = playback
            super.init()
        }

        private func player(isFullScreen: Bool) -> AnyView {
            AnyView(
                NavigationStack {
                    PlayerView(isFullScreen: isFullScreen, toggleFullScreen: { [weak self] in
                        self?.toggleFullScreen()
                    })
                    .ignoresSafeArea(.container, edges: .all)
                }
                .toolbarVisibility(.hidden, for: .windowToolbar)
                .environment(playback)
            )
        }

        func attachPlayer(to parent: NSView) {
            let host: NSHostingView<AnyView>
            if let hostingView {
                host = hostingView
                host.removeFromSuperview()
            } else {
                host = NSHostingView(rootView: player(isFullScreen: false))
                hostingView = host
            }
            host.frame = parent.bounds
            host.autoresizingMask = [.width, .height]
            parent.addSubview(host)
        }

        private func toggleFullScreen() {
            guard !transitioning else { return }
            if let fullscreenWindow {
                transitioning = true
                fullscreenWindow.toggleFullScreen(nil)
                return
            }
            guard let container, let mainWindow = container.window else { return }
            let window = NSWindow(
                contentRect: mainWindow.contentLayoutRect,
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "Dusk Playback"
            window.backgroundColor = .black
            window.collectionBehavior = [.fullScreenPrimary]
            window.delegate = self
            let content = NSView(frame: NSRect(origin: .zero, size: mainWindow.contentLayoutRect.size))
            window.contentView = content
            fullscreenWindow = window
            detached.wrappedValue = true
            attachPlayer(to: content)
            hostingView?.rootView = player(isFullScreen: true)
            transitioning = true
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
        }

        func windowDidEnterFullScreen(_ notification: Notification) {
            transitioning = false
        }

        func windowDidExitFullScreen(_ notification: Notification) {
            restoreInlinePlayer()
        }

        func windowDidFailToEnterFullScreen(_ window: NSWindow) {
            restoreInlinePlayer()
        }

        func windowDidFailToExitFullScreen(_ window: NSWindow) {
            transitioning = false
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            playback.showPlayer = false
            return false
        }

        private func restoreInlinePlayer() {
            guard let container else { return }
            attachPlayer(to: container)
            hostingView?.rootView = player(isFullScreen: false)
            closeFullscreenWindow()
            detached.wrappedValue = false
            container.window?.makeKeyAndOrderFront(nil)
        }

        private func closeFullscreenWindow() {
            fullscreenWindow?.delegate = nil
            fullscreenWindow?.orderOut(nil)
            fullscreenWindow?.close()
            fullscreenWindow = nil
            transitioning = false
        }

        func tearDown() {
            hostingView?.removeFromSuperview()
            hostingView = nil
            closeFullscreenWindow()
        }
    }
}
