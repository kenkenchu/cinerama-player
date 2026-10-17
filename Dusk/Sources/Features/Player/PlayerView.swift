import AppKit
import SwiftUI

struct PlayerView: View {
    var isFullScreen = false
    var toggleFullScreen: () -> Void
    @State private var controlsVisible = true
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black
            if let engine = playback.engine, let source = playback.playbackSource {
                MacPlayerSession(engine: engine, source: source, playback: playback, isFullScreen: isFullScreen, controlsVisible: $controlsVisible, toggleFullScreen: toggleFullScreen)
                    .id(playback.playerPresentationID)
            }
            if playback.playerLoadingState.isVisible {
                ProgressView().controlSize(.large).padding(24).background(.regularMaterial, in: .capsule)
            }
            if let error = playback.loadError {
                VStack(spacing: 20) {
                    Text("Couldn't Play").font(.title)
                    Text(error).multilineTextAlignment(.center)
                    Button("Close") { playback.dismissFailedPlayback() }
                }.padding(40).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            }
        }
        .overlay(alignment: .topLeading) {
            Button("Close Player", systemImage: "xmark") { playback.showPlayer = false }
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close Player (Esc)")
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding(24)
                .padding(.top, isFullScreen ? 32 : 0)
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)
        }
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .playerSharePlayPresentation(isPlayer: true)
        .onChange(of: scenePhase) { _, phase in playback.flushTimelineForScenePhase(phase) }
    }
}

private struct MacPlayerSession: View {
    let source: PlaybackSource
    let playback: PlaybackCoordinator
    let isFullScreen: Bool
    let toggleFullScreen: () -> Void
    @Binding var controlsVisible: Bool
    @State private var model: PlayerViewModel
    @State private var activity: NSObjectProtocol?
    @State private var lastPointerLocation: CGPoint?
    @State private var showsDebugInfo = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(engine: any PlaybackEngine, source: PlaybackSource, playback: PlaybackCoordinator, isFullScreen: Bool, controlsVisible: Binding<Bool>, toggleFullScreen: @escaping () -> Void) {
        self.toggleFullScreen = toggleFullScreen
        self.isFullScreen = isFullScreen
        _controlsVisible = controlsVisible
        self.source = source
        self.playback = playback
        _model = State(initialValue: PlayerViewModel(engine: engine, markers: playback.activeItemDetails?.markers ?? [], liveTVContext: source.liveTVContext))
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            model.engineView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { videoInteractionSurface }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 12) {
                        if let marker = model.activeSkipMarker {
                            HStack {
                                Spacer()
                                Button(marker.isIntro ? "Skip Intro" : "Skip Credits") { model.skipActiveMarker() }
                                    .buttonStyle(.glass)
                            }
                        }
                        if let next = playback.upNextPoster {
                            HStack {
                                Spacer()
                                Button("Play Next Episode") { playback.playUpNextPosterNow() }
                                    .buttonStyle(.glass)
                                Button("Dismiss", systemImage: "xmark") { playback.dismissUpNextPoster(userInitiated: true) }
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(next.isStarting ? "Starting next episode" : "Next episode available")
                        }
                        if playback.upNextPresentation != nil {
                            HStack {
                                Text("Next Episode").font(.headline)
                                Button("Play Now") { playback.playUpNextNow() }
                                Button("Close") { playback.showPlayer = false }
                            }.padding().background(.regularMaterial, in: .capsule)
                        }
                        controls
                            .onHover { hovering in
                                if hovering { model.beginControlsInteractionHold() }
                                else { model.endControlsInteractionHold() }
                            }
                            .opacity(model.showControls ? 1 : 0)
                            .allowsHitTesting(model.showControls)
                            .accessibilityHidden(!model.showControls)
                    }.padding(24)
                }
            if let error = model.playbackError, !playback.isAutomaticDirectPlayFallbackPending {
                VStack {
                    Text(error.localizedDescription)
                    Button("Close") { playback.showPlayer = false }
                }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if showsDebugInfo {
                debugOverlay
                    .padding(24)
                    .padding(.top, isFullScreen ? 32 : 0)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // Layout updates can repeat hover callbacks without pointer movement.
                guard location != lastPointerLocation else { return }
                lastPointerLocation = location
                model.touchControls()
            case .ended:
                lastPointerLocation = nil
            }
        }
        .simultaneousGesture(TapGesture().onEnded { model.touchControls() })
        .onChange(of: model.showControls, initial: true) { _, visible in
            controlsVisible = visible
        }
        .onChange(of: isFullScreen) { _, _ in model.touchControls() }
        .task { configure() }
        .onDisappear {
            model.playbackSnapshotHandler = nil
            model.cleanup()
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
        }
        .onChange(of: playback.externalSubtitleRefreshToken) {
            model.reloadExternalSubtitleStreams(part: playback.debugInfo?.part, selecting: playback.consumePendingExternalSubtitleStreamID())
        }
        .onChange(of: playback.activeLiveTVContext) { _, context in model.liveTVContext = context }
    }

    /// Capture video clicks separately from control/menu clicks. An exclusive
    /// gesture keeps a fullscreen double-click from also toggling playback.
    private var videoInteractionSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .pointerStyle(.link)
            .gesture(
                TapGesture(count: 2).exclusively(before: TapGesture(count: 1))
                    .onEnded { action in
                        switch action {
                        case .first:
                            model.touchControls()
                            toggleFullScreen()
                        case .second:
                            model.togglePlayPause()
                        }
                    }
            )
            .help("Click to play or pause; double-click for fullscreen")
            .accessibilityLabel("Video playback")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.togglePlayPause() }
    }

    private var playbackTitle: String {
        guard let details = playback.activeItemDetails else {
            return source.liveTVContext?.channel.title ?? "Dusk"
        }
        if details.type == .episode {
            let numbering = MediaTextFormatter.compactSeasonEpisodeLabel(
                season: details.parentIndex, episode: details.index
            )
            return [details.grandparentTitle?.nilIfEmpty, numbering, details.title]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        return details.title
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack {
                Text(MediaTextFormatter.playbackDuration(milliseconds: Int(model.currentTime * 1000)) ?? "0:00").monospacedDigit()
                Slider(value: Binding(get: { model.isScrubbing ? model.scrubPosition : model.currentTime },
                                      set: { model.updateScrub(to: $0) }),
                       in: (model.seekableRange ?? 0...max(model.duration, 1)),
                       onEditingChanged: { editing in
                           if editing { model.beginScrub() } else { model.endScrub() }
                       })
                    .accessibilityLabel("Playback position")
                Text(MediaTextFormatter.playbackDuration(milliseconds: Int(model.duration * 1000)) ?? "0:00").monospacedDigit()
            }
            .font(.caption.monospacedDigit())
            HStack(spacing: 12) {
                Button("Back 10 Seconds", systemImage: "gobackward.10") { model.seek(to: model.currentTime - 10, revealControls: true, precise: false) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("Back 10 Seconds (←)")
                Button(model.state == .playing ? "Pause" : "Play", systemImage: model.state == .playing ? "pause.fill" : "play.fill") { model.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                    .help(model.state == .playing ? "Pause (Space)" : "Play (Space)")
                Button("Forward 10 Seconds", systemImage: "goforward.10") { model.seek(to: model.currentTime + 10, revealControls: true, precise: false) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("Forward 10 Seconds (→)")
                Text(playbackTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(playbackTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Playback Debug Info", systemImage: "gearshape", isOn: $showsDebugInfo)
                    .toggleStyle(.button)
                    .keyboardShortcut("i", modifiers: .command)
                    .help("Playback Debug Info (⌘I)")
                if model.liveTVContext != nil { Button("Go Live") { model.goLive() } }
                Menu("Audio", systemImage: "speaker.wave.2") {
                    ForEach(model.audioTracks) { track in
                        Button(track.displayTitle) { model.selectAudio(track) }
                    }
                }
                .help("Choose an audio track")
                Menu("Subtitles", systemImage: "captions.bubble") {
                    Picker("Subtitle track", selection: Binding<Int?>(
                        get: { model.selectedSubtitleTrackID },
                        set: { trackID in
                            if let trackID {
                                guard let track = model.subtitleTracks.first(where: { $0.id == trackID }) else { return }
                                model.selectSubtitle(track)
                            } else {
                                model.selectSubtitle(nil)
                            }
                        }
                    )) {
                        Text("Off").tag(Optional<Int>.none)
                        ForEach(model.subtitleTracks) { track in
                            Text(track.displayTitle).tag(Optional(track.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .help("Choose a subtitle track")
                if let info = playback.debugInfo, info.canSelectPlaybackQuality {
                    Menu("Quality", systemImage: "slider.horizontal.3") {
                        ForEach(info.availableQualityPresets) { preset in
                            Button(preset.displayName) { Task { await playback.switchQuality(to: preset) } }
                        }
                    }
                    .help("Playback quality for this session")
                }
                Button(
                    isFullScreen ? "Exit Full Screen" : "Enter Full Screen",
                    systemImage: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                ) {
                    model.touchControls()
                    toggleFullScreen()
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
                .help(isFullScreen ? "Exit Full Screen (⌃⌘F)" : "Enter Full Screen (⌃⌘F)")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .buttonStyle(.borderless)
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        // A uniform fill composites directly over native video and letterboxing;
        // a backdrop material can sample a different AppKit surface underneath.
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.black.opacity(reduceTransparency ? 1 : 0.45))
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var debugOverlay: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Playback Debug Info").font(.headline)
                    Spacer()
                    Button("Close Debug Info", systemImage: "xmark") { showsDebugInfo = false }
                        .labelStyle(.iconOnly)
                }
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(Array(debugRows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                Text(row.0).foregroundStyle(.secondary)
                                Text(row.1).textSelection(.enabled)
                            }
                        }
                    }
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .frame(width: 380, height: 380)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
    }

    private var debugRows: [(String, String)] {
        var rows: [(String, String)] = [
            ("State", String(describing: model.state)),
            ("Position", String(format: "%.1f / %.1f s", model.currentTime, model.duration)),
            ("Buffering", model.isBuffering ? "Yes" : "No"),
            ("Subtitle", model.selectedSubtitleTrack?.displayTitle ?? "Off"),
            ("Subtitle codec", model.selectedSubtitleTrack?.codec ?? "Unknown")
        ]
        if let info = playback.debugInfo {
            rows.insert(contentsOf: [
                ("Engine", info.engineLabel),
                ("Route", info.decisionLabel),
                ("Plex playback", info.plexPlaybackLabel),
                ("Plex video", info.processingLabel(info.serverDecisions?.videoDecision)),
                ("Plex audio", info.processingLabel(info.serverDecisions?.audioDecision)),
                ("Video", "\(info.videoLabel) · \(info.resolutionLabel)"),
                ("Audio", info.audioLabel),
                ("Container", info.containerLabel),
                ("Reason", info.resolverLabel)
            ], at: 0)
        }
        rows.append(contentsOf: model.engine.renderingDiagnostics)
        return rows
    }

    private func configure() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Playing video")
        model.externalSubtitleURLProvider = { playback.plexService.externalSubtitleURL(for: $0, serverID: playback.activePlaybackServerID) }
        model.externalSubtitleRestartHandler = { playback.switchToVLCKitForExternalSubtitle(streamID: $0) }
        // Capture the session scope so a later profile/item change cannot redirect the write.
        let profileID = playback.plexService.activeProfileID
        let serverID = playback.activePlaybackServerID
        let mediaDetails = playback.activeItemDetails
        let preferences = playback.preferences
        model.subtitleSelectionHandler = { track in
            preferences.rememberSubtitle(track, profileID: profileID, serverID: serverID, mediaDetails: mediaDetails)
        }
        model.configureAutomaticTrackSelection(
            preferences: playback.preferences, part: playback.debugInfo?.part,
            mediaDetails: playback.activeItemDetails,
            usesServerTrackSelection: playback.usesServerTrackSelection,
            rendersServerSubtitleTrack: playback.isSpatialAudioSession,
            selectedAudioStreamID: playback.activeAudioStreamID,
            selectedSubtitleStreamID: playback.activeSubtitleStreamID,
            pendingExternalSubtitleStreamID: playback.consumePendingExternalSubtitleStreamID(),
            explicitTrackSelection: playback.consumePendingExplicitTrackSelection(),
            spentAutoSkipMarkerIDs: playback.spentAutoSkipMarkerIDs,
            savedSubtitlePreference: preferences.savedSubtitlePreference(profileID: profileID, serverID: serverID, mediaDetails: mediaDetails))
        model.autoSkipHandler = { marker in model.handleSkipMarker(marker) }
        model.autoSkipSpentHandler = { playback.noteAutoSkipSpent(markerID: $0) }
        model.upNextPosterHandler = { marker in
            if let marker {
                let presentationID = playback.playerPresentationID
                let ratingKey = playback.ratingKey
                Task { await playback.presentUpNextPosterIfPossible(creditsMarkerID: marker.id, isEstimated: marker.isEstimated, presentationID: presentationID, ratingKey: ratingKey) }
            } else { playback.dismissUpNextPoster() }
        }
        model.playbackSnapshotHandler = { state, _, _ in playback.noteActivePlaybackState(state) }
        model.bufferingPresentationHandler = { playback.setBufferingPresentationVisible($0, for: playback.playerPresentationID) }
        model.transcodeAudioFallbackHandler = { track in Task { await playback.transcodeForUndecodableAudio(track) } }
        model.plexTrackSelectionHandler = { audio, subtitle in playback.selectPlexStreamsForPlayback(audioStreamID: audio, subtitleStreamID: subtitle) }
        model.startPlaybackIfNeeded(source: source)
    }
}
