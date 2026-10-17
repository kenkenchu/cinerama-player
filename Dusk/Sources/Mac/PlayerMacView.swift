#if os(macOS)
import AppKit
import SwiftUI

struct PlayerView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black
            if let engine = playback.engine, let source = playback.playbackSource {
                MacPlayerSession(engine: engine, source: source, playback: playback)
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
        .preferredColorScheme(.dark)
        .playerSharePlayPresentation(isPlayer: true)
        .onChange(of: scenePhase) { _, phase in playback.flushTimelineForScenePhase(phase) }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Close Player", systemImage: "xmark") { playback.showPlayer = false }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            ToolbarItem {
                Button("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { NSApp.keyWindow?.toggleFullScreen(nil) }
                    .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }
    }
}

private struct MacPlayerSession: View {
    let source: PlaybackSource
    let playback: PlaybackCoordinator
    @State private var model: PlayerViewModel
    @State private var activity: NSObjectProtocol?

    init(engine: any PlaybackEngine, source: PlaybackSource, playback: PlaybackCoordinator) {
        self.source = source
        self.playback = playback
        _model = State(initialValue: PlayerViewModel(engine: engine, markers: playback.activeItemDetails?.markers ?? [], liveTVContext: source.liveTVContext))
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            model.engineView
            VStack(spacing: 12) {
                Spacer()
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
            }.padding(24)
            if let error = model.playbackError, !playback.isAutomaticDirectPlayFallbackPending {
                VStack {
                    Text(error.localizedDescription)
                    Button("Close") { playback.showPlayer = false }
                }.padding(32).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

    private var controls: some View {
        VStack(spacing: 12) {
            Text(playback.activeItemDetails?.title ?? source.liveTVContext?.channel.title ?? "Dusk")
                .font(.headline).lineLimit(1)
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
            HStack(spacing: 20) {
                Button("Back 10 Seconds", systemImage: "gobackward.10") { model.seek(to: model.currentTime - 10, revealControls: true, precise: false) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button(model.state == .playing ? "Pause" : "Play", systemImage: model.state == .playing ? "pause.fill" : "play.fill") { model.togglePlayPause() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Forward 10 Seconds", systemImage: "goforward.10") { model.seek(to: model.currentTime + 10, revealControls: true, precise: false) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Spacer()
                if model.liveTVContext != nil { Button("Go Live") { model.goLive() } }
                Menu("Audio", systemImage: "speaker.wave.2") {
                    ForEach(model.audioTracks) { track in
                        Button(track.displayTitle) { model.selectAudio(track) }
                    }
                }
                Menu("Subtitles", systemImage: "captions.bubble") {
                    Button("Off") { model.selectSubtitle(nil) }
                    ForEach(model.subtitleTracks) { track in
                        Button(track.displayTitle) { model.selectSubtitle(track) }
                    }
                }
                if let info = playback.debugInfo, info.canSelectPlaybackQuality {
                    Menu("Quality", systemImage: "slider.horizontal.3") {
                        ForEach(info.availableQualityPresets) { preset in
                            Button(preset.displayName) { Task { await playback.switchQuality(to: preset) } }
                        }
                    }
                }
            }
            .labelStyle(.iconOnly)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
    }

    private func configure() {
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Playing video")
        model.externalSubtitleURLProvider = { playback.plexService.externalSubtitleURL(for: $0, serverID: playback.activePlaybackServerID) }
        model.externalSubtitleRestartHandler = { playback.switchToVLCKitForExternalSubtitle(streamID: $0) }
        model.configureAutomaticTrackSelection(
            preferences: playback.preferences, part: playback.debugInfo?.part,
            mediaDetails: playback.activeItemDetails,
            usesServerTrackSelection: playback.usesServerTrackSelection,
            rendersServerSubtitleTrack: playback.isSpatialAudioSession,
            selectedAudioStreamID: playback.activeAudioStreamID,
            selectedSubtitleStreamID: playback.activeSubtitleStreamID,
            pendingExternalSubtitleStreamID: playback.consumePendingExternalSubtitleStreamID(),
            explicitTrackSelection: playback.consumePendingExplicitTrackSelection(),
            spentAutoSkipMarkerIDs: playback.spentAutoSkipMarkerIDs)
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
#endif
