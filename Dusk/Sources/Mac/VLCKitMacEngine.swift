#if os(macOS)
import AppKit
import AVFoundation
import SwiftUI
import VLCKit

/// Desktop VLC uses its native NSView output and Core Audio, independently of
/// the mobile engine's audio-session and UIKit rendering workarounds.
@MainActor @Observable
final class VLCKitEngine: NSObject, PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isBuffering = false
    private(set) var error: PlaybackError?
    private(set) var availableSubtitleTracks: [SubtitleTrack] = []
    private(set) var availableAudioTracks: [AudioTrack] = []
    var selectedSubtitleTrackID: Int? { Int(player.currentVideoSubTitleIndex) >= 0 ? Int(player.currentVideoSubTitleIndex) : nil }
    var selectedAudioTrackID: Int? { Int(player.currentAudioTrackIndex) >= 0 ? Int(player.currentAudioTrackIndex) : nil }
    var videoEnhancementStatus: VideoEnhancementStatus { .init(state: .unavailable, reason: "Native desktop VLC renderer") }
    var onPlaybackEnded: (@MainActor () -> Void)?
    var supportsExternalSubtitles: Bool { true }
    var playbackCoordinator: AVPlaybackCoordinator { coordinator }

    @ObservationIgnored private let videoView = VLCVideoView()
    @ObservationIgnored private let player: VLCMediaPlayer
    @ObservationIgnored private var coordinator: AVDelegatingPlaybackCoordinator!
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    @ObservationIgnored private var source: PlaybackSource?
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var subtitleSize: SubtitleFontSize = .default
    @ObservationIgnored private var itemIdentifier: String?
    @ObservationIgnored private var commandGeneration = UUID()
    @ObservationIgnored private var slaves: [(URL, Bool)] = []
    @ObservationIgnored private var externalTrackURLs: [Int: URL] = [:]
    @ObservationIgnored private var tracksBeforeSlave: Set<Int> = []
    @ObservationIgnored private var pendingSlaveURL: URL?

    override init() {
        player = VLCMediaPlayer()
        super.init()
        videoView.fillScreen = false
        player.drawable = videoView
        coordinator = AVDelegatingPlaybackCoordinator(playbackControlDelegate: self)
    }
    deinit { timer?.invalidate() }

    func load(source: PlaybackSource) {
        stop()
        self.source = source
        ended = false
        error = nil
        currentTime = 0
        duration = 0
        slaves = []
        externalTrackURLs = [:]
        state = .loading
        let media = VLCMedia(url: source.url)
        media.addOption(":network-caching=\(PlaybackBufferPolicy.vlcCachingMilliseconds(for: source.locality))")
        media.addOption(":freetype-rel-fontsize=\(PlaybackSubtitleStyle.vlcRelativeFontSize(for: subtitleSize))")
        if let start = source.startPosition, start > 0 { media.addOption(":start-time=\(start)") }
        if let audio = source.preferredAudioTrackPosition { media.addOption(":audio-track=\(audio)") }
        if !source.shouldAutoPlay { media.addOption(":start-paused") }
        player.media = media
        player.play()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sync() }
        }
        configureCoordinatedPlayback(itemIdentifier: itemIdentifier)
    }
    func configureVideoEnhancement(_ request: VideoEnhancementRequest) {}
    func play() { player.play() }
    func pause() { player.pause() }
    func stop() {
        commandGeneration = UUID()
        timer?.invalidate()
        timer = nil
        player.stop()
        state = .stopped
        isBuffering = false
    }
    func seek(to position: TimeInterval) {
        let target = max(0, duration > 0 ? min(position, duration) : position)
        player.time = VLCTime(int: Int32(clamping: Int64(target * 1000)))
        currentTime = target
    }
    func setPlaybackRate(_ rate: Float) { player.rate = rate }
    func recoverFromStall() { player.play() }
    func handleReturnToForeground() { videoView.needsDisplay = true }
    func setVideoFillEnabled(_ enabled: Bool) { videoView.fillScreen = enabled }
    func applySubtitleFontSize(_ size: SubtitleFontSize) {
        subtitleSize = size
        // The desktop text renderer reads its relative size when opening media.
    }
    func selectSubtitleTrack(_ track: SubtitleTrack?) { player.currentVideoSubTitleIndex = Int32(track?.id ?? -1) }
    func selectAudioTrack(_ track: AudioTrack) { player.currentAudioTrackIndex = Int32(track.id) }
    func attachExternalSubtitle(_ url: URL, select: Bool) -> Bool {
        if slaves.contains(where: { $0.0 == url }) { return true }
        tracksBeforeSlave = Set((player.videoSubTitlesIndexes as? [NSNumber] ?? []).map(\.intValue))
        guard player.addPlaybackSlave(url, type: .subtitle, enforce: select) == 0 else { return false }
        slaves.append((url, select))
        pendingSlaveURL = url
        return true
    }
    func makePlayerView() -> AnyView { AnyView(VLCMacSurface(view: videoView)) }
    func configureCoordinatedPlayback(itemIdentifier: String?) {
        self.itemIdentifier = itemIdentifier
        commandGeneration = UUID()
        coordinator.transitionToItem(withIdentifier: itemIdentifier, proposingInitialTimingBasedOn: nil)
    }
    private func sync() {
        let rawState = player.state
        isBuffering = rawState == .buffering && !player.isPlaying
        switch rawState {
        case .playing: state = .playing
        case .paused: state = .paused
        case .opening: state = .loading
        case .buffering: if state != .playing { state = .loading }
        case .error:
            error = .unknown("VLC could not play this media.")
            state = .error
        case .ended:
            state = .stopped
            if !ended { ended = true; onPlaybackEnded?() }
        default: break
        }
        currentTime = max(0, Double(player.time.intValue) / 1000)
        duration = max(0, Double(player.media?.length.intValue ?? 0) / 1000)
        let audioIDs = player.audioTrackIndexes as? [NSNumber] ?? []
        let audioNames = player.audioTrackNames as? [String] ?? []
        availableAudioTracks = zip(audioIDs, audioNames).compactMap { id, name in
            guard id.intValue >= 0 else { return nil }
            return AudioTrack(id: id.intValue, displayTitle: name, language: nil, languageCode: nil, codec: nil, channels: nil, channelLayout: nil)
        }
        let subtitleIDs = player.videoSubTitlesIndexes as? [NSNumber] ?? []
        let subtitleNames = player.videoSubTitlesNames as? [String] ?? []
        if let url = pendingSlaveURL, let newID = subtitleIDs.first(where: { $0.intValue >= 0 && !tracksBeforeSlave.contains($0.intValue) }) {
            externalTrackURLs[newID.intValue] = url
            pendingSlaveURL = nil
        }
        availableSubtitleTracks = zip(subtitleIDs, subtitleNames).compactMap { id, name in
            guard id.intValue >= 0 else { return nil }
            let url = externalTrackURLs[id.intValue]
            return SubtitleTrack(id: id.intValue, displayTitle: name, language: nil, languageCode: nil, codec: nil, isForced: false, isHearingImpaired: false, isExternal: url != nil, externalURL: url)
        }
    }
}

private struct VLCMacSurface: NSViewRepresentable {
    let view: VLCVideoView
    func makeNSView(context: Context) -> VLCVideoView { view }
    func updateNSView(_ view: VLCVideoView, context: Context) {}
}

extension VLCKitEngine: AVPlaybackCoordinatorPlaybackControlDelegate {
    nonisolated func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorPlayCommand, completionHandler: @escaping @Sendable () -> Void) {
        let identifier = command.expectedCurrentItemIdentifier
        let time = CMTimeGetSeconds(command.itemTime)
        let host = command.hostClockTime
        let rate = command.rate
        Task { @MainActor [weak self] in
            guard let self, self.itemIdentifier == identifier else { completionHandler(); return }
            let generation = UUID()
            self.commandGeneration = generation
            let delay = CMTimeGetSeconds(CMTimeSubtract(host, CMClockGetTime(CMClockGetHostTimeClock())))
            if time.isFinite { self.seek(to: time + max(0, -delay) * Double(rate)) }
            completionHandler()
            if delay.isFinite && delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard self.commandGeneration == generation else { return }
            self.setPlaybackRate(rate)
            self.play()
        }
    }
    nonisolated func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorPauseCommand, completionHandler: @escaping @Sendable () -> Void) {
        let identifier = command.expectedCurrentItemIdentifier
        Task { @MainActor [weak self] in
            if let self, self.itemIdentifier == identifier { self.commandGeneration = UUID(); self.pause() }
            completionHandler()
        }
    }
    nonisolated func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorSeekCommand, completionHandler: @escaping @Sendable () -> Void) {
        let identifier = command.expectedCurrentItemIdentifier
        let time = CMTimeGetSeconds(command.itemTime)
        Task { @MainActor [weak self] in
            if let self, self.itemIdentifier == identifier, time.isFinite { self.commandGeneration = UUID(); self.pause(); self.seek(to: time) }
            completionHandler()
        }
    }
    nonisolated func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorBufferingCommand, completionHandler: @escaping @Sendable () -> Void) { completionHandler() }
}
#endif
