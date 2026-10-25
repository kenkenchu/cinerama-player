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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var playbackIsDetached = false
    @State private var selection: MacDestination = .home
    @State private var destinationBeforeSearch: MacDestination = .home
    @State private var hoveredInstrument: MacDestination?
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
        .background(Color.clear)
        .background {
            MacSearchEscapeHandler {
                guard selection == .search, !playback.showPlayer else { return false }
                selection = destinationBeforeSearch
                hoveredInstrument = nil
                return true
            }
        }
        .task(id: plex.serverContentRevision) {
            if libraries == nil { libraries = LibrariesViewModel(plexService: plex) }
            if liveTV == nil { liveTV = LiveTVViewModel(plexService: plex) }
            await libraries?.loadLibraries()
            await liveTV?.discover()
        }
        .onChange(of: playback.showPlayer) { _, shown in
            if shown { hoveredInstrument = nil }
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
        .onChange(of: selection) { previous, current in
            if current == .search, previous != .search {
                destinationBeforeSearch = previous
            }
            if playback.showPlayer { playback.showPlayer = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cineramaShowSearch)) { _ in
            selection = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .cineramaSelectDestination)) { notification in
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
            if reduceTransparency {
                CockpitHousing().fill(Color.cineramaSurface)
            }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: CockpitHousing())
        .overlay {
            CockpitHousing()
                .stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .padding(0.5)
                .overlay { CockpitPanelEtching() }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.30), radius: 12, y: 6)
        // Outside the clipped housing so labels can extend above the console.
        .overlayPreferenceValue(CockpitTooltipAnchor.self) { anchor in
            GeometryReader { geometry in
                if let anchor, let item = hoveredInstrument {
                    HStack(spacing: 10) {
                        Text(item.rawValue).fontWeight(.semibold)
                        Text("⌘\(item.shortcutNumber)")
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                    .fixedSize()
                    .position(x: geometry[anchor].midX, y: geometry[anchor].minY - 24)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
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
                .onHover { isHovered in
                    if isHovered { hoveredInstrument = item }
                    else if hoveredInstrument == item { hoveredInstrument = nil }
                }
                .anchorPreference(key: CockpitTooltipAnchor.self, value: .bounds) { anchor in
                    hoveredInstrument == item ? anchor : nil
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

/// Handle Escape at the catalog window boundary so the search field's native
/// cancel handling cannot consume it before navigation gets a chance.
private struct MacSearchEscapeHandler: NSViewRepresentable {
    let handleEscape: () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(handleEscape: handleEscape) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handleEscape = handleEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var handleEscape: () -> Bool
        private weak var view: NSView?
        private var monitor: Any?

        init(handleEscape: @escaping () -> Bool) { self.handleEscape = handleEscape }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, event.keyCode == 53,
                          event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                          let window = self.view?.window,
                          event.window === window, window.isKeyWindow,
                          window.attachedSheet == nil else { return false }
                    return self.handleEscape()
                }
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private struct CockpitTooltipAnchor: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// A chamfered glass housing gives the console a physical silhouette while
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
            .buttonStyle(CockpitInstrumentStyle(symbol: symbol, isSelected: isSelected))
            .pointerStyle(.link)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// ButtonStyle's pressed state provides immediate feedback without replacing
/// native button activation, focus, keyboard shortcuts or accessibility.
private struct CockpitInstrumentStyle: ButtonStyle {
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
            Capsule()
                .fill(.white.opacity(isSelected ? 0.95 : 0))
                .frame(width: 18, height: 2)
                .shadow(color: .white.opacity(isSelected ? 0.6 : 0), radius: 4)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.70))
        .frame(width: 76)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.07 : (isHovered ? 0.035 : 0)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(isSelected ? 0.20 : 0), lineWidth: 0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .opacity(configuration.isPressed ? 0.65 : 1)
        .brightness(isHovered && isEnabled ? 0.035 : 0)
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

struct CineramaMacCommands: Commands {
    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(MacDestination.allCases) { item in
                Button(item.rawValue, systemImage: item.symbol) {
                    NotificationCenter.default.post(name: .cineramaSelectDestination, object: item.rawValue)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(item.shortcutNumber))), modifiers: .command)
            }
        }
        CommandGroup(after: .textEditing) {
            Button("Search Library") { NotificationCenter.default.post(name: .cineramaShowSearch, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let cineramaShowSearch = Notification.Name("CineramaShowSearch")
    static let cineramaSelectDestination = Notification.Name("CineramaSelectDestination")
}

/// Fullscreen animation and key handling must agree on one presentation phase.
struct MacPlaybackWindowState {
    enum Phase: Equatable { case inline, enteringFullscreen, fullscreen, exitingFullscreen, closed }
    enum EscapeAction: Equatable { case ignore, exitFullscreen, dismissPlayback }
    private(set) var phase: Phase = .inline

    var isTransitioning: Bool { phase == .enteringFullscreen || phase == .exitingFullscreen }

    mutating func beginEntering() -> Bool {
        guard phase == .inline else { return false }
        phase = .enteringFullscreen
        return true
    }

    mutating func didEnter() {
        guard phase == .enteringFullscreen else { return }
        phase = .fullscreen
    }

    mutating func beginExiting() -> Bool {
        guard phase == .fullscreen else { return false }
        phase = .exitingFullscreen
        return true
    }

    mutating func didRestoreInline() {
        guard phase != .closed else { return }
        phase = .inline
    }

    mutating func failedToExit() {
        guard phase == .exitingFullscreen else { return }
        phase = .fullscreen
    }

    func escapeAction(isRepeat: Bool) -> EscapeAction {
        guard !isRepeat else { return .ignore }
        switch phase {
        case .inline: return .dismissPlayback
        case .fullscreen: return .exitFullscreen
        case .enteringFullscreen, .exitingFullscreen, .closed: return .ignore
        }
    }

    mutating func close() { phase = .closed }
}

@MainActor @Observable
private final class MacPlaybackPresentation {
    var isFullScreen = false
}

/// Stable SwiftUI root: changing windows must not replace the navigation stack
/// or construct a second renderer for the same engine.
private struct MacPlaybackContent: View {
    let playback: PlaybackCoordinator
    let presentation: MacPlaybackPresentation
    let toggleFullScreen: () -> Void
    let exitPlayback: () -> Void

    var body: some View {
        NavigationStack {
            PlayerView(isFullScreen: presentation.isFullScreen,
                       toggleFullScreen: toggleFullScreen, exitPlayback: exitPlayback)
                .ignoresSafeArea(.container, edges: .all)
        }
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .environment(playback)
    }
}

/// Reparents one hosting view so fullscreen never recreates the player session
/// or changes the catalog window's fullscreen state.
struct MacPlaybackHost: NSViewRepresentable {
    let playback: PlaybackCoordinator
    @Binding var isDetached: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(playback: playback, detached: $isDetached)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.updateContainer(container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateContainer(nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        let playback: PlaybackCoordinator
        private weak var container: NSView?
        private var hostingView: NSHostingView<MacPlaybackContent>?
        private var fullscreenWindow: NSWindow?
        private var escapeMonitor: Any?
        private var windowState = MacPlaybackWindowState()
        private let presentation = MacPlaybackPresentation()
        private let detached: Binding<Bool>

        init(playback: PlaybackCoordinator, detached: Binding<Bool>) {
            self.detached = detached
            self.playback = playback
            super.init()
        }

        func updateContainer(_ container: NSView) {
            self.container = container
            // SwiftUI can update/replace the inline NSView while its player is
            // detached. Remember the current destination; only attach inline.
            if windowState.phase == .inline { attachPlayer(to: container) }
        }

        func attachPlayer(to parent: NSView) {
            guard windowState.phase != .closed else { return }
            let host: NSHostingView<MacPlaybackContent>
            if let hostingView {
                host = hostingView
            } else {
                host = NSHostingView(rootView: MacPlaybackContent(
                    playback: playback, presentation: presentation,
                    toggleFullScreen: { [weak self] in self?.toggleFullScreen() },
                    exitPlayback: { [weak self] in self?.handleEscape(isRepeat: false) }
                ))
                hostingView = host
                installEscapeMonitor()
            }
            if host.superview !== parent {
                host.removeFromSuperview()
                parent.addSubview(host)
            }
            host.frame = parent.bounds
            host.autoresizingMask = [.width, .height]
            parent.needsLayout = true
            host.layoutSubtreeIfNeeded()
        }

        private func handleEscape(isRepeat: Bool) {
            switch windowState.escapeAction(isRepeat: isRepeat) {
            case .ignore: break
            case .exitFullscreen: toggleFullScreen()
            case .dismissPlayback: playback.showPlayer = false
            }
        }

        private func installEscapeMonitor() {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, self.playback.showPlayer,
                          event.keyCode == 53,
                          event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                          let window = self.hostingView?.window,
                          event.window === window, window.isKeyWindow,
                          window.attachedSheet == nil else { return false }
                    self.handleEscape(isRepeat: event.isARepeat)
                    return true
                }
                return handled ? nil : event
            }
        }

        private func toggleFullScreen() {
            guard playback.showPlayer, !windowState.isTransitioning else { return }
            if let fullscreenWindow {
                guard windowState.beginExiting() else { return }
                fullscreenWindow.toggleFullScreen(nil)
                return
            }
            guard let container, let mainWindow = container.window,
                  windowState.beginEntering() else { return }
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
            presentation.isFullScreen = true
            detached.wrappedValue = true
            attachPlayer(to: content)
            window.makeKeyAndOrderFront(nil)
            window.toggleFullScreen(nil)
        }

        private func owns(_ notification: Notification) -> Bool {
            guard windowState.phase != .closed, let window = notification.object as? NSWindow else { return false }
            return window === fullscreenWindow
        }

        func windowWillEnterFullScreen(_ notification: Notification) {
            guard owns(notification) else { return }
            _ = windowState.beginEntering()
        }

        func windowDidEnterFullScreen(_ notification: Notification) {
            guard owns(notification) else { return }
            windowState.didEnter()
        }

        func windowWillExitFullScreen(_ notification: Notification) {
            guard owns(notification) else { return }
            _ = windowState.beginExiting()
        }

        func windowDidExitFullScreen(_ notification: Notification) {
            guard owns(notification) else { return }
            restoreInlinePlayer()
        }

        func windowDidFailToEnterFullScreen(_ window: NSWindow) {
            guard window === fullscreenWindow, windowState.phase != .closed else { return }
            restoreInlinePlayer()
        }

        func windowDidFailToExitFullScreen(_ window: NSWindow) {
            guard window === fullscreenWindow, windowState.phase != .closed else { return }
            windowState.failedToExit()
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard sender === fullscreenWindow else { return true }
            playback.showPlayer = false
            return false
        }

        private func restoreInlinePlayer() {
            guard windowState.phase != .closed, let container else { return }
            // Reattach and lay out before revealing the player in the main
            // window, then retire the old window without delegate callbacks.
            attachPlayer(to: container)
            presentation.isFullScreen = false
            windowState.didRestoreInline()
            detached.wrappedValue = false
            let mainWindow = container.window
            closeFullscreenWindow()
            mainWindow?.makeKeyAndOrderFront(nil)
        }

        private func closeFullscreenWindow() {
            let window = fullscreenWindow
            fullscreenWindow = nil
            window?.delegate = nil
            window?.orderOut(nil)
            window?.close()
        }

        func tearDown() {
            windowState.close()
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
