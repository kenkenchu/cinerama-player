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
        engine = ExperimentalMPEG2Engine(mode: .cpu)
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack(alignment: .bottom) {
            TVMPEG2Surface(display: playback.engine.display).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Text("LIVE").foregroundStyle(.red).bold()
                    Text(channel.displayTitle).font(.title3)
                    Spacer()
                    Text(playback.engine.mode.label).foregroundStyle(.secondary)
                }
                if let message = playback.message ?? playback.engine.error?.localizedDescription {
                    Text(message).multilineTextAlignment(.center)
                } else if playback.engine.isBuffering || playback.engine.state == .idle {
                    ProgressView("Tuning channel…")
                }
                HStack(spacing: 40) {
                    Button(playback.wantsPlayback ? "Pause" : "Play") { playback.togglePause() }
                        .disabled(playback.message != nil || playback.engine.error != nil)
                    Menu("Audio") {
                        ForEach(playback.engine.availableAudioTracks) { track in
                            Button((track.id == playback.engine.selectedAudioTrackID ? "✓ " : "") + track.displayTitle) {
                                playback.engine.selectAudioTrack(track)
                            }.disabled(!track.isDecodable)
                        }
                    }.disabled(playback.engine.availableAudioTracks.isEmpty)
                    Button("Playback Information") { information = true }
                    Button("Back to Channels") { dismiss() }
                }
            }
            .padding(40).background(.ultraThinMaterial)
        }
        .background(.black)
        .task { await playback.start(provider: provider, channel: channel, serverID: serverID) }
        .onPlayPauseCommand { playback.togglePause() }
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
        override func layoutSubviews() { super.layoutSubviews(); display.frame = bounds }
    }
}
