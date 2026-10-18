import AVFoundation
import AVKit
import SwiftUI

/// Feasibility-only AVPlayer session. No Mac player UI or AppKit hosts are
/// compiled into this target. Uses shared Plex copy-only decision/reporting APIs.
@MainActor
@Observable
final class TVPlaybackCoordinator {
    let player = AVPlayer()
    var loading = false
    var errorMessage: String?
    var route = "Direct Play"
    var progressMessage: String?
    private let service: PlexService
    private let details: PlexMediaDetails
    private let choice: TVPlaybackChoice
    private let startPosition: Double
    private let sessionID = UUID().uuidString
    private var transcodeID: String?
    private var generation = UUID()
    private var statusObservation: NSKeyValueObservation?
    private var clockTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var started = false
    private var stopped = false
    private var remuxAttempted = false
    private var readyItem: AVPlayerItem?
    private var canReport = false
    private var lastPosition: Double = 0

    init(service: PlexService, details: PlexMediaDetails, choice: TVPlaybackChoice, resume: Bool) {
        self.service = service
        self.details = details
        self.choice = choice
        startPosition = resume ? Double(details.viewOffset ?? 0) / 1000 : 0
    }

    func start() {
        guard !started else { return }
        started = true
        let attempt = generation
        startupTask = Task { await load(remux: choice.requiresRemux, position: startPosition, attempt: attempt) }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, !self.stopped else { return }
                if self.canReport { await self.report() }
                if let id = self.transcodeID {
                    await self.service.pingTranscodeSession(transcodeSessionID: id, serverID: self.details.serverID)
                }
            }
        }
    }

    private func load(remux: Bool, position: Double, attempt: UUID) async {
        guard generation == attempt, !stopped else { return }
        loading = true
        errorMessage = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            if let restriction = await service.remoteStreamingRestriction(forServerID: details.serverID) {
                throw TVPlaybackFailure.unsupported(restriction.message)
            }
            let url: URL
            if remux {
                remuxAttempted = true
                let id = UUID().uuidString
                transcodeID = id
                let result = try await service.spatialAudioRemuxURL(
                    ratingKey: details.ratingKey, mediaIndex: choice.mediaIndex,
                    sessionIdentifier: sessionID, transcodeSessionID: id,
                    audioStreamID: choice.audio?.id, subtitleStreamID: nil,
                    serverID: details.serverID)
                guard generation == attempt, !stopped else {
                    await service.stopTranscodeSession(transcodeSessionID: id, serverID: details.serverID)
                    return
                }
                guard case .transcodeAvailable = result.outcome, result.streams.isLosslessRemux else {
                    throw TVPlaybackFailure.unsupported("Plex could not offer a copy-only HLS stream for this file. Server video/audio conversion is disabled. Try another HD title or version.")
                }
                url = result.url
                route = "Direct Stream · Video copy · Audio copy"
            } else {
                guard let directURL = service.directPlayURL(for: choice.part, serverID: details.serverID) else {
                    throw TVPlaybackFailure.unsupported("The media file is unavailable on its Plex server.")
                }
                url = directURL
                route = "Direct Play"
            }
            try Task.checkCancellation()
            guard generation == attempt, !stopped else { return }
            let item = AVPlayerItem(url: url)
            let title = AVMutableMetadataItem()
            title.identifier = .commonIdentifierTitle
            title.value = details.title as NSString
            item.externalMetadata = [title]
            // Sidecars and Plex subtitle persistence are deferred. Native
            // embedded track selection remains available in AVKit's controls.
            player.appliesMediaSelectionCriteriaAutomatically = false
            readyItem = nil
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let status = item.status
                Task { @MainActor [weak self] in
                    self?.handle(status: status, item: item, position: position, attempt: attempt)
                }
            }
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == attempt, !self.stopped else { return }
                    await self.report(state: .stopped)
                }
            }
            player.replaceCurrentItem(with: item)
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.generation == attempt,
                      !self.stopped, self.loading else { return }
                self.handle(status: .failed, item: item, position: position, attempt: attempt)
            }
        } catch is CancellationError {
        } catch {
            guard generation == attempt, !stopped else { return }
            loading = false
            errorMessage = (error as? TVPlaybackFailure)?.errorDescription
                ?? "Playback could not start. Check the server connection or try another HD title."
            if let id = transcodeID {
                transcodeID = nil
                await service.stopTranscodeSession(transcodeSessionID: id, serverID: details.serverID)
            }
        }
    }

    private func handle(status: AVPlayerItem.Status, item: AVPlayerItem, position: Double, attempt: UUID) {
        guard generation == attempt, !stopped, player.currentItem === item else { return }
        switch status {
        case .readyToPlay:
            guard readyItem !== item else { return }
            readyItem = item
            timeoutTask?.cancel()
            // Off initially; the native menu can select supported embedded tracks.
            Task {
                if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                    guard generation == attempt, !stopped, player.currentItem === item else { return }
                    item.select(nil, in: group)
                }
            }
            startupTask = Task {
                if position > 0 {
                    await player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
                }
                guard generation == attempt, !stopped else { return }
                lastPosition = position
                canReport = true
                loading = false
                player.play()
                await report(state: .playing)
            }
        case .failed:
            timeoutTask?.cancel()
            statusObservation = nil
            startupTask?.cancel()
            player.pause()
            if !remuxAttempted {
                let current = player.currentTime().seconds
                let resumePosition = current.isFinite && current > 0 ? current : position
                canReport = false
                let fallbackAttempt = UUID()
                generation = fallbackAttempt
                startupTask = Task { await load(remux: true, position: resumePosition, attempt: fallbackAttempt) }
            } else {
                loading = false
                errorMessage = "AVPlayer could not decode this copy-only stream. Try another HD version. VLC playback is not included in this prototype."
            }
        default: break
        }
    }

    private func report(state: PlaybackState? = nil, position: Double? = nil) async {
        let seconds = position ?? player.currentTime().seconds
        if seconds.isFinite { lastPosition = max(0, seconds) }
        let time = Int(lastPosition * 1000)
        let duration = details.duration ?? 0
        let playbackState = state ?? (player.timeControlStatus == .playing ? .playing : .paused)
        do {
            try await service.submitTimeline(ratingKey: details.ratingKey, key: details.key,
                state: playbackState, timeMs: time, durationMs: duration,
                sessionIdentifier: sessionID, serverID: details.serverID)
            progressMessage = "Progress synced to Plex"
        } catch { progressMessage = "Plex progress sync unavailable" }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        generation = UUID()
        startupTask?.cancel()
        clockTask?.cancel()
        timeoutTask?.cancel()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.pause()
        let seconds = player.currentTime().seconds
        if seconds.isFinite { lastPosition = max(0, seconds) }
        player.replaceCurrentItem(with: nil)
        let id = transcodeID
        transcodeID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let stoppedPosition = lastPosition
        Task {
            if canReport { await report(state: .stopped, position: stoppedPosition) }
            if let id { await service.stopTranscodeSession(transcodeSessionID: id, serverID: details.serverID) }
        }
    }
}

struct TVPlayerScreen: View {
    @State var playback: TVPlaybackCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVNativePlayer(player: playback.player) { dismiss() }.ignoresSafeArea()
            if playback.loading { ProgressView("Preparing original-quality playback…").padding(40).background(.black.opacity(0.85)) }
            if let message = playback.errorMessage {
                VStack(spacing: 30) {
                    Text("Unable to Play").font(.title)
                    Text(message).multilineTextAlignment(.center)
                    Button("Back to Details") { dismiss() }
                }.padding(80).background(.black.opacity(0.95))
            }
        }
        .task { playback.start() }
        .onDisappear { playback.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { playback.player.pause() }
        }
    }
}

struct TVNativePlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let close: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(close: close) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = false
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
            close()
            return false
        }
    }
}
