import AppKit
import SwiftUI

private enum MacDestination: String, CaseIterable, Identifiable {
    case home = "Home", movies = "Movies", shows = "TV Shows", videos = "Videos"
    case liveTV = "Live TV", search = "Search", downloads = "Downloads", settings = "Settings"
    var id: Self { self }
    var shortcutNumber: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
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
    @State private var selection: MacDestination = .home
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
        .onReceive(NotificationCenter.default.publisher(for: .duskSelectDestination)) { notification in
            guard let name = notification.object as? String,
                  let destination = MacDestination(rawValue: name) else { return }
            selection = destination
        }
    }

    /// Playback is a sibling above this shell, never a replacement for a
    /// NavigationStack root that may have a pushed detail destination.
    private var navigationShell: some View {
        Group {
            if let libraries, let liveTV {
                destination(selection, libraries: libraries, liveTV: liveTV)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            navigationConsole
        }
    }

    private var navigationConsole: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                HStack(spacing: 10) {
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    Text("CINERAMA")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .tracking(1.5)
                }
                .accessibilityElement(children: .combine)
                Divider().frame(height: 36)
                navigationInstruments
            }
            navigationInstruments
        }
        .padding(12)
        .background {
            CockpitHousing()
                .fill(LinearGradient(
                    colors: [Color(white: 0.19), Color(white: 0.075), Color(white: 0.10)],
                    startPoint: .top, endPoint: .bottom
                ))
        }
        .clipShape(CockpitHousing())
        .overlay {
            CockpitHousing()
                .stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .padding(0.5)
                .overlay {
                    CockpitHousing()
                        .stroke(.black.opacity(0.65), lineWidth: 1)
                        .padding(3)
                }
                .overlay { CockpitPanelEtching() }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.30), radius: 12, y: 6)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var navigationInstruments: some View {
        HStack(spacing: 6) {
            ForEach(MacDestination.allCases) { item in
                MacNavigationInstrument(
                    title: item.rawValue,
                    symbol: item.symbol,
                    shortcutNumber: item.shortcutNumber,
                    isSelected: selection == item
                ) {
                    selection = item
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation instruments")
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

/// An opaque graphite housing gives the console a physical silhouette while
/// keeping its established dimensions and navigation behavior.
private struct CockpitHousing: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(18, min(rect.width, rect.height) / 3)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

private struct CockpitPanelEtching: View {
    var body: some View {
        Canvas { context, size in
            var rails = Path()
            for y in [CGFloat(6), size.height - 6] {
                rails.move(to: CGPoint(x: 32, y: y))
                rails.addLine(to: CGPoint(x: size.width - 32, y: y))
            }
            context.stroke(rails, with: .color(.white.opacity(0.10)), lineWidth: 0.5)
            for x in [CGFloat(14), size.width - 14] {
                for y in [CGFloat(14), size.height - 14] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)),
                                 with: .color(.black.opacity(0.7)))
                    var slot = Path()
                    slot.move(to: CGPoint(x: x - 1, y: y + 1))
                    slot.addLine(to: CGPoint(x: x + 1, y: y - 1))
                    context.stroke(slot, with: .color(.white.opacity(0.35)), lineWidth: 0.75)
                }
            }
        }
    }
}

private struct MacNavigationInstrument: View {
    let title: String
    let symbol: String
    let shortcutNumber: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(CockpitInstrumentStyle(title: title, symbol: symbol, isSelected: isSelected))
            .pointerStyle(.link)
            .help("\(title) (⌘\(shortcutNumber))")
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// ButtonStyle's pressed state provides tactile feedback without replacing
/// native button activation, focus, keyboard shortcuts or accessibility.
private struct CockpitInstrumentStyle: ButtonStyle {
    let title: String
    let symbol: String
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .symbolVariant(isSelected ? .fill : .none)
                .font(.system(.title3, weight: .medium))
                .frame(height: 22)
                .shadow(color: .white.opacity(isSelected ? 0.35 : 0), radius: 6)
            Text(title)
                .font(.system(.caption, design: .monospaced, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Capsule()
                .fill(.white.opacity(isSelected ? 0.95 : 0.12))
                .frame(width: 18, height: 2)
                .shadow(color: .white.opacity(isSelected ? 0.6 : 0), radius: 4)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.70))
        .frame(width: 76)
        .padding(.vertical, 10)
        .background {
            let face = RoundedRectangle(cornerRadius: 16, style: .continuous)
            face.fill(.black.opacity(0.75))
            face.fill(LinearGradient(
                colors: [Color(white: isSelected ? 0.24 : 0.13), Color(white: 0.055)],
                startPoint: .top, endPoint: .bottom
            ))
            .padding(2)
            .offset(y: configuration.isPressed ? 1 : 0)
            face.strokeBorder(
                LinearGradient(colors: [.white.opacity(isSelected || isHovered ? 0.45 : 0.16), .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1
            )
            face.strokeBorder(.white.opacity(isSelected ? 0.18 : 0.04), lineWidth: 0.5)
                .padding(3)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(.white.opacity(isSelected ? 0.65 : 0.08))
                .frame(width: 26, height: 1)
                .padding(.top, 5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .offset(y: configuration.isPressed ? 1 : 0)
        .brightness(isHovered && isEnabled ? 0.035 : 0)
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

struct DuskMacCommands: Commands {
    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(MacDestination.allCases) { item in
                Button(item.rawValue, systemImage: item.symbol) {
                    NotificationCenter.default.post(name: .duskSelectDestination, object: item.rawValue)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(item.shortcutNumber))), modifiers: .command)
            }
        }
        CommandGroup(after: .textEditing) {
            Button("Search Library") { NotificationCenter.default.post(name: .duskShowSearch, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let duskShowSearch = Notification.Name("DuskShowSearch")
    static let duskSelectDestination = Notification.Name("DuskSelectDestination")
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
        private var escapeMonitor: Any?
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
                installEscapeMonitor()
            }
            host.frame = parent.bounds
            host.autoresizingMask = [.width, .height]
            parent.addSubview(host)
        }

        private func installEscapeMonitor() {
            // The catalog may retain first responder when this separate hosting
            // view appears. Handle Escape independently of SwiftUI focus.
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, self.playback.showPlayer,
                          event.keyCode == 53,
                          event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                          let window = self.hostingView?.window,
                          event.window === window, window.isKeyWindow,
                          window.attachedSheet == nil else { return false }
                    if self.fullscreenWindow != nil {
                        self.toggleFullScreen()
                    } else {
                        self.playback.showPlayer = false
                    }
                    return true
                }
                return handled ? nil : event
            }
        }

        private func toggleFullScreen() {
            guard !transitioning else { return }
            if let fullscreenWindow {
                transitioning = true
                fullscreenWindow.toggleFullScreen(nil)
                return
            }
            guard let container, let mainWindow = container.window else { return }
            // contentLayoutRect is window-local; a new window needs screen coordinates.
            // Preserve the playback display even when it is not the primary display.
            let playbackRect = mainWindow.convertToScreen(container.convert(container.bounds, to: nil))
            let window = NSWindow(
                contentRect: playbackRect,
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false, screen: mainWindow.screen
            )
            window.isReleasedWhenClosed = false
            window.title = "Cinerama Playback"
            window.backgroundColor = .black
            window.collectionBehavior = [.fullScreenPrimary]
            window.delegate = self
            let content = NSView(frame: NSRect(origin: .zero, size: playbackRect.size))
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
            if let escapeMonitor {
                NSEvent.removeMonitor(escapeMonitor)
                self.escapeMonitor = nil
            }
            hostingView?.removeFromSuperview()
            hostingView = nil
            closeFullscreenWindow()
        }
    }
}
