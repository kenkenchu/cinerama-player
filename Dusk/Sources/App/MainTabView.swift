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
    @State private var window: NSWindow?
    @State private var isFullScreen = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var savedColumnVisibility: NavigationSplitViewVisibility?
    @State private var selection: MacDestination? = .home
    @State private var paths: [MacDestination: NavigationPath] = [:]
    @State private var libraries: LibrariesViewModel?
    @State private var liveTV: LiveTVViewModel?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(MacDestination.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Dusk")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            if playback.showPlayer {
                PlayerView(isFullScreen: isFullScreen, toggleFullScreen: { window?.toggleFullScreen(nil) })
                    .ignoresSafeArea(isFullScreen ? .all : [], edges: .all)
            } else if let libraries, let liveTV {
                destination(selection ?? .home, libraries: libraries, liveTV: liveTV)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MacPlaybackWindowReader { window in
            self.window = window
            isFullScreen = window.styleMask.contains(.fullScreen)
            updatePlayerColumns()
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            guard let changedWindow = notification.object as? NSWindow, changedWindow === window else { return }
            isFullScreen = true
            updatePlayerColumns()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            guard let changedWindow = notification.object as? NSWindow, changedWindow === window else { return }
            isFullScreen = false
            updatePlayerColumns()
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
            updatePlayerColumns()
            if !shown { playback.onPlayerDismissed() }
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

    private func updatePlayerColumns() {
        if playback.showPlayer && isFullScreen {
            if savedColumnVisibility == nil {
                savedColumnVisibility = columnVisibility
                columnVisibility = .detailOnly
            }
        } else if let savedColumnVisibility {
            columnVisibility = savedColumnVisibility
            self.savedColumnVisibility = nil
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

/// Resolves the owning window without relying on whichever window is currently key.
private struct MacPlaybackWindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class WindowView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.onWindow?(window)
            }
        }
    }
}
