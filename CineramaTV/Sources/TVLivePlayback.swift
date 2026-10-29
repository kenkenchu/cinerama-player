import AVFoundation
import SwiftUI
import UIKit

/// A TV-owned session around the shared decoder. Library AVKit stays independent.
@MainActor @Observable
final class TVLivePlayback {
    let engine: ExperimentalMPEG2Engine
    private(set) var message: String?
    private(set) var started = false
    private(set) var stopped = false
    private(set) var wantsPlayback = true
    private var tune: PlexLiveTuneResult?
    private let service: PlexService
    private let tuneChannel: @MainActor (PlexLiveTVProvider, PlexLiveChannel, String?) async throws -> PlexLiveTuneResult
    private let releaseTune: (@MainActor (PlexLiveTuneResult) async -> Void)?
    private let identity: ServerSessionToken
    private var heartbeat: Task<Void, Never>?
    private var timeline: Task<Void, Never>?
    private var finalization: Task<Void, Never>?

    init(service: PlexService,
         tuneChannel: (@MainActor (PlexLiveTVProvider, PlexLiveChannel, String?) async throws -> PlexLiveTuneResult)? = nil,
         releaseTune: (@MainActor (PlexLiveTuneResult) async -> Void)? = nil) {
        self.service = service
        self.tuneChannel = tuneChannel ?? { provider, channel, serverID in
            try await service.tuneLiveTV(provider: provider, channel: channel, serverID: serverID)
        }
        self.releaseTune = releaseTune
        identity = service.serverSessionToken
        engine = ExperimentalMPEG2Engine(mode: .cpu, inputBufferDuration: 2)
    }

    static func validate(_ tune: PlexLiveTuneResult) throws {
        if let decisions = tune.serverDecisions, !decisions.isLosslessRemux {
            throw TVPlaybackFailure.unsupported("Plex must confirm video and audio copy. Server conversion is disabled.")
        }
        if tune.transcodeSessionID != nil && tune.serverDecisions == nil {
            throw TVPlaybackFailure.unsupported("Plex did not confirm copy-only delivery.")
        }
        let video = tune.part.streams.first { $0.streamType == .video }
        let resolution = tune.media.videoResolution?.lowercased() ?? ""
        if resolution.contains("4k") || resolution.contains("uhd")
            || [tune.media.width, video?.width].compactMap({ $0 }).contains(where: { $0 > 1920 })
            || [tune.media.height, video?.height].compactMap({ $0 }).contains(where: { $0 > 1080 }) {
            throw TVPlaybackFailure.unsupported("Apple TV HD requires an HD channel. UHD playback and downscaling are unavailable.")
        }
        let transfer = video?.colorTrc?.lowercased() ?? ""
        guard video?.doviPresent != true, video?.doviProfile == nil,
              !["smpte2084", "arib-std-b67", "pq", "hlg"].contains(transfer),
              video?.colorPrimaries?.lowercased() != "bt2020", (video?.bitDepth ?? 8) <= 8 else {
            throw TVPlaybackFailure.unsupported("The TV Live TV experiment supports HD SDR 8-bit MPEG-2 only.")
        }
        let codec = tune.serverDecisions?.videoCodec ?? tune.media.videoCodec
        if let codec, !ExperimentalMPEG2Mode.applies(codec: codec, forceAVPlayer: false, forceVLC: false, airPlay: false) {
            throw TVPlaybackFailure.unsupported("The TV experiment supports MPEG-2 channels only. Library playback remains available separately.")
        }
        // Missing codec/dimensions are checked against the actual bitstream by
        // the native decoder; metadata cannot authorize UHD or another codec.
    }

    func start(provider: PlexLiveTVProvider, channel: PlexLiveChannel, serverID: String?) async {
        guard !started, !stopped else { return }
        started = true
        do {
            if let restriction = await service.remoteStreamingRestriction(forServerID: serverID) {
                throw TVPlaybackFailure.unsupported(restriction.message)
            }
            guard !Task.isCancelled, !stopped, identity == service.serverSessionToken else { return }
            let result = try await tuneChannel(provider, channel, serverID)
            guard !Task.isCancelled, !stopped, identity == service.serverSessionToken else {
                await cleanUp(result)
                return
            }
            tune = result
            try Self.validate(result)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            engine.load(url: result.playbackURL, shouldAutoPlay: wantsPlayback)
            report()
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled, let self, !self.stopped else { return }
                    guard self.identity == self.service.serverSessionToken else { self.stop(); return }
                    self.report()
                    if let id = self.tune?.transcodeSessionID {
                        await self.service.pingTranscodeSession(transcodeSessionID: id, serverID: result.serverID)
                    }
                }
            }
        } catch {
            message = (error as? TVPlaybackFailure)?.errorDescription ?? "Could not tune this channel. Check the Plex server and try again."
            if let tune { self.tune = nil; await cleanUp(tune) }
        }
    }

    func togglePause() {
        guard !stopped else { return }
        wantsPlayback.toggle()
        if wantsPlayback { engine.play() } else { engine.pause() }
        report()
    }

    func setForeground(_ active: Bool) {
        if active { engine.recoverAfterForeground() }
        else { wantsPlayback = false; engine.pause(); report() }
    }

    private func report() {
        guard let tune, !stopped else { return }
        let state = engine.state
        let time = Int(engine.currentTime * 1000)
        let previous = timeline
        timeline = Task {
            await previous?.value
            guard identity == service.serverSessionToken else { return }
            await service.reportTimeline(ratingKey: tune.sessionID, key: "/livetv/sessions/\(tune.sessionID)",
                state: state, timeMs: time, durationMs: 0,
                sessionIdentifier: tune.playbackSessionIdentifier, serverID: tune.serverID)
        }
    }

    private func cleanUp(_ tune: PlexLiveTuneResult) async {
        // A dismissed view's .task is cancelled. Cleanup needs an independent
        // task so URLSession can still release the server session.
        let cleanup = Task { @MainActor in
            if let releaseTune { await releaseTune(tune); return }
            // Never report a retired profile using a new profile's token.
            guard identity == service.serverSessionToken else { return }
            await service.reportTimeline(ratingKey: tune.sessionID, key: "/livetv/sessions/\(tune.sessionID)",
                state: .stopped, timeMs: 0, durationMs: 0,
                sessionIdentifier: tune.playbackSessionIdentifier, serverID: tune.serverID)
            if let id = tune.transcodeSessionID {
                await service.stopTranscodeSession(transcodeSessionID: id, serverID: tune.serverID)
            }
        }
        await cleanup.value
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        wantsPlayback = false
        heartbeat?.cancel(); heartbeat = nil
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let retired = tune; tune = nil
        let previous = timeline
        finalization = Task {
            await previous?.value
            if let retired { await cleanUp(retired) }
        }
    }

    func finish() async { stop(); await finalization?.value }
}

struct TVLivePlayerScreen: View {
    let provider: PlexLiveTVProvider
    let channel: PlexLiveChannel
    let serverID: String?
    @State var playback: TVLivePlayback
    @State private var information = false
    @State private var audioSelection = false
    @State private var moreActions = false
    @State private var controlsVisible = true
    @State private var interaction = 0
    @FocusState private var focus: Control?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Control: Hashable { case surface, play, audio, more }
    private var controlsKey: String {
        "\(interaction)|\(controlsVisible)|\(playback.engine.state)|\(playback.wantsPlayback)|\(information)|\(audioSelection)|\(moreActions)"
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack(alignment: .bottom) {
            TVMPEG2Surface(display: playback.engine.display).ignoresSafeArea()
            Button {
                revealControls()
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(TVLiveSurfaceButtonStyle()).focusEffectDisabled()
            .focused($focus, equals: .surface)
            .accessibilityLabel("Show playback controls")
            .disabled(controlsVisible)
            if controlsVisible {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 20) {
                        Label("LIVE", systemImage: "circle.fill")
                            .font(.caption.bold()).foregroundStyle(.red)
                        Text(channel.displayTitle).font(.title3.bold()).lineLimit(1)
                        Spacer()
                    }
                    if let message = playback.message ?? playback.engine.error?.localizedDescription {
                        Text(message).multilineTextAlignment(.leading)
                    } else if playback.engine.isBuffering || playback.engine.state == .idle {
                        ProgressView("Tuning channel…")
                    }
                    HStack(spacing: 32) {
                        Button(
                            playback.wantsPlayback ? "Pause" : "Play",
                            systemImage: playback.wantsPlayback ? "pause.fill" : "play.fill"
                        ) {
                            playback.togglePause()
                            revealControls()
                        }
                        .modifier(TVDeckActionStyle(prominent: true))
                        .focused($focus, equals: .play)
                        .disabled(playback.message != nil || playback.engine.error != nil)
                        Button("Audio", systemImage: "speaker.wave.2") { audioSelection = true }
                            .modifier(TVDeckActionStyle()).focused($focus, equals: .audio)
                            .disabled(playback.engine.availableAudioTracks.isEmpty)
                        Button("More", systemImage: "ellipsis") { moreActions = true }
                            .modifier(TVDeckActionStyle()).focused($focus, equals: .more)
                        Spacer()
                    }
                }
                .padding(32)
                .background(
                    reduceTransparency ? Color.black : Color.black.opacity(0.75),
                    in: RoundedRectangle(cornerRadius: 28)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, TVDeckLayout.horizontalInset)
                .padding(.bottom, TVDeckLayout.verticalInset)
                .transition(.opacity)
            }
        }
        .background(.black)
        .task { await playback.start(provider: provider, channel: channel, serverID: serverID) }
        .onAppear { focus = .play }
        .onPlayPauseCommand {
            playback.togglePause()
            revealControls()
        }
        .onMoveCommand { _ in revealControls() }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            revealControls()
        }
        .onChange(of: playback.engine.state) { _, state in
            if state != .playing { revealControls() }
        }
        .onChange(of: focus) { _, _ in interaction += 1 }
        .task(id: controlsKey) {
            guard controlsVisible, playback.wantsPlayback, playback.engine.state == .playing,
                !UIAccessibility.isVoiceOverRunning,
                !information, !audioSelection, !moreActions
            else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { controlsVisible = false }
            focus = .surface
        }
        .confirmationDialog("Live TV", isPresented: $moreActions, titleVisibility: .visible) {
            Button("Playback Information") { information = true }
            Button("Back to Channels") { dismiss() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $audioSelection) {
            NavigationStack {
                List {
                    ForEach(playback.engine.availableAudioTracks) { track in
                        Button {
                            playback.engine.selectAudioTrack(track)
                            audioSelection = false
                        } label: {
                            HStack {
                                Text(track.displayTitle)
                                Spacer()
                                if track.id == playback.engine.selectedAudioTrackID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }.disabled(!track.isDecodable)
                    }
                }.navigationTitle("Audio")
            }
        }
        .onExitCommand { dismiss() }
        .onDisappear { playback.stop() }
        .onChange(of: phase) { _, value in playback.setForeground(value == .active) }
        .sheet(isPresented: $information) {
            NavigationStack {
                List {
                    ForEach(playback.engine.renderingDiagnostics, id: \.0) { fact in
                        LabeledContent(fact.0, value: fact.1)
                    }
                }.navigationTitle("Live Playback Information")
            }
        }
    }
    private func revealControls() {
        interaction += 1
        if !controlsVisible {
            controlsVisible = true
            focus = .play
        }
    }

}

/// The full-screen focus target must never acquire a system button background.
/// tvOS plain buttons can still draw a bright focused plate over the video when
/// the controls auto-hide. Return only the transparent label in every state.
private struct TVLiveSurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct TVMPEG2Surface: UIViewRepresentable {
    let display: AVSampleBufferDisplayLayer
    func makeUIView(context: Context) -> Surface { Surface(display: display) }
    func updateUIView(_ view: Surface, context: Context) {}
    final class Surface: UIView {
        let display: AVSampleBufferDisplayLayer
        init(display: AVSampleBufferDisplayLayer) {
            self.display = display
            super.init(frame: .zero)
            backgroundColor = .black
            display.videoGravity = .resizeAspect
            layer.addSublayer(display)
        }
        required init?(coder: NSCoder) { nil }
        override func layoutSubviews() {
            super.layoutSubviews()
            display.frame = bounds
        }
    }
}
