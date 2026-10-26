import AppKit
import AVFoundation
import CineramaMPEG2
import SwiftUI

/// Mac-only opt-in. The same FFmpeg pipeline runs with CPU IDCT or Metal IDCT.
/// Standard VLC remains the default, with its full track/subtitle/seek behavior.
enum ExperimentalMPEG2Mode: String, CaseIterable, Identifiable {
    static let defaultsKey = "experimentalLiveMPEG2Mode"
    case standard, cpu, metal
    var id: Self { self }
    var label: String {
        switch self {
        case .standard: "Standard playback"
        case .cpu: "Experimental CPU"
        case .metal: "Experimental Metal"
        }
    }
    static var current: Self { Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .standard }
    static func applies(codec: String?, forceAVPlayer: Bool, forceVLC: Bool, airPlay: Bool) -> Bool {
        !forceAVPlayer && !forceVLC && !airPlay && ["mpeg2video", "mpeg2", "mp2v"].contains(codec?.lowercased() ?? "")
    }
}

private struct MPEG2ReadFailure: Error {
    let error: PlaybackError
    let recoverable: Bool
}
private final class MPEG2NativeSession: @unchecked Sendable {
    let decoder: OpaquePointer
    init(metal: Bool) throws {
        guard let decoder = cm2_create(metal ? 1 : 0) else {
            throw PlaybackError.unknown("Could not initialize the experimental MPEG-2 decoder.")
        }
        self.decoder = decoder
    }
    deinit { cm2_close(decoder) }
    func cancel() { cm2_cancel(decoder) }
    func open(_ url: URL) throws {
        guard cm2_open(decoder, url.absoluteString) == 0 else { throw failure }
    }
    var failure: MPEG2ReadFailure { .init(error: .unknown(String(cString: cm2_error(decoder))), recoverable: cm2_retryable(decoder) != 0) }
    func audioTracks() -> [AudioTrack] {
        (0..<cm2_audio_track_count(decoder)).map { position in
            let language = String(cString: cm2_audio_track_language(decoder, position))
            let codec = String(cString: cm2_audio_track_codec(decoder, position))
            let channels = Int(cm2_audio_track_channels(decoder, position))
            let display = [language.isEmpty ? "Audio \(position + 1)" : language, codec.uppercased(), "\(channels) ch"].joined(separator: " · ")
            var track = AudioTrack(id: Int(cm2_audio_track_id(decoder, position)), displayTitle: display,
                language: nil, languageCode: language.isEmpty ? nil : language, codec: codec,
                channels: channels, channelLayout: nil)
            track.isDecodable = cm2_audio_track_supported(decoder, position) != 0
            return track
        }
    }
    func next() throws -> MPEG2DecodedSample? {
        var kind: Int32 = 0
        guard let sample = cm2_next(decoder, &kind) else {
            if kind < 0 { throw failure }
            return nil
        }
        return .init(sample: sample, kind: kind, audioTrackID: Int(cm2_selected_audio(decoder)), blocks: cm2_gpu_blocks(decoder), gpuSeconds: cm2_gpu_seconds(decoder))
    }
}
private struct MPEG2DecodedSample: @unchecked Sendable {
    let sample: CMSampleBuffer
    let kind: Int32
    let audioTrackID: Int
    let blocks: UInt64
    let gpuSeconds: Double
}

@MainActor @Observable
final class ExperimentalMPEG2Engine: NSObject, PlaybackEngine {
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    var duration: TimeInterval { 0 }
    var supportsSeeking: Bool { false }
    var supportsTrackSelection: Bool { false }
    var supportsAudioTrackSelection: Bool { true }
    var seekableTimeRange: ClosedRange<TimeInterval>? { nil }
    private(set) var isBuffering = false
    private(set) var error: PlaybackError?
    var availableSubtitleTracks: [SubtitleTrack] { [] }
    private(set) var availableAudioTracks: [AudioTrack] = []
    var selectedSubtitleTrackID: Int? { nil }
    private(set) var selectedAudioTrackID: Int?
    var prefersSpatializedAudioSession: Bool { false }
    var videoEnhancementStatus: VideoEnhancementStatus { .init(state: .unavailable, reason: "Experimental MPEG-2 renderer") }
    var onPlaybackEnded: (@MainActor () -> Void)?
    var playbackCoordinator: AVPlaybackCoordinator { coordinator }
    let mode: ExperimentalMPEG2Mode
    private(set) var gpuBlocks: UInt64 = 0
    private(set) var gpuSeconds = 0.0
    private(set) var buffers = LivePlaybackBufferState()
    private(set) var outputAudioChannels = 0
    private(set) var outputAudioRate = 0.0
    private(set) var recovery = LiveStreamRecoveryPolicy()
    private(set) var timestampResets = 0
    private(set) var submittedVideoFrames = 0
    private(set) var lateVideoSubmissions = 0
    private(set) var outputVideoWidth = 0
    private(set) var outputVideoHeight = 0
    private(set) var outputVideoCadence = 0.0
    @ObservationIgnored private let surface = MPEG2VideoSurface()
    @ObservationIgnored private let audio = AVSampleBufferAudioRenderer()
    @ObservationIgnored private let synchronizer = AVSampleBufferRenderSynchronizer()
    @ObservationIgnored private var coordinator: AVDelegatingPlaybackCoordinator!
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var session: MPEG2NativeSession?
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var origin: CMTime?
    @ObservationIgnored private var desiredRate: Float = 1
    @ObservationIgnored private var clockStarted = false
    @ObservationIgnored private var flushID = UUID()
    @ObservationIgnored private var outputReady = true
    @ObservationIgnored private var pendingRestart = false
    @ObservationIgnored private var elapsedBeforeRecovery = 0.0
    @ObservationIgnored private var pauseBegan: TimeInterval?
    @ObservationIgnored private var lastProgress = 0.0
    @ObservationIgnored private var lastVideoPTS: TimeInterval?
    @ObservationIgnored private var lastAudioPTS: TimeInterval?
    @ObservationIgnored private var preferredAudio: AudioTrack?
    @ObservationIgnored nonisolated(unsafe) private var outputObservers: [NSObjectProtocol] = []

    init(mode: ExperimentalMPEG2Mode) {
        self.mode = mode
        super.init()
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        synchronizer.addRenderer(surface.display.sampleBufferRenderer)
        synchronizer.addRenderer(audio)
        coordinator = AVDelegatingPlaybackCoordinator(playbackControlDelegate: self)
        for name in [Notification.Name.AVSampleBufferAudioRendererWasFlushedAutomatically,
                     Notification.Name.AVSampleBufferAudioRendererOutputConfigurationDidChange] {
            outputObservers.append(NotificationCenter.default.addObserver(forName: name, object: audio, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.requestRecovery() }
            })
        }
    }
    deinit { worker?.cancel(); session?.cancel(); timer?.invalidate(); outputObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    func load(source: PlaybackSource) {
        stop()
        let id = UUID(); generation = id
        state = .loading; isBuffering = true; error = nil
        desiredRate = source.shouldAutoPlay ? 1 : 0
        let mode = mode
        lastProgress = ProcessInfo.processInfo.systemUptime
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            while !Task.isCancelled {
                do {
                    let session = try MPEG2NativeSession(metal: mode == .metal)
                    guard let self, await self.attach(session, id: id) else { return }
                    try session.open(source.url)
                    let tracks = session.audioTracks()
                    let selected = Int(cm2_selected_audio(session.decoder))
                    await self.setAudioTracks(tracks, selected: selected, id: id)
                    while !Task.isCancelled, let decoded = try session.next() {
                        guard await self.isCurrent(id) else { return }
                        await self.prepareTimestamp(decoded)
                        let waitBegan = ProcessInfo.processInfo.systemUptime
                        while !Task.isCancelled {
                            guard await self.isCurrent(id) else { return }
                            if await self.restartNeeded(waitBegan: waitBegan) {
                                throw MPEG2ReadFailure(error: .unknown("Live output needs rebuffering."), recoverable: true)
                            }
                            if await self.ready(decoded) { break }
                            try await Task.sleep(for: .milliseconds(5))
                        }
                        try Task.checkCancellation()
                        await self.enqueue(decoded, id: id)
                    }
                    try Task.checkCancellation()
                    throw MPEG2ReadFailure(error: .unknown("The Live TV stream ended."), recoverable: true)
                } catch is CancellationError { return }
                catch {
                    guard let self else { return }
                    let native = error as? MPEG2ReadFailure
                    let safe = native?.error ?? error as? PlaybackError ?? .unknown("Experimental MPEG-2 playback failed.")
                    guard let delay = await self.prepareRecovery(error: safe, recoverable: native?.recoverable ?? false, id: id) else { return }
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateClock() }
        }
    }
    private func attach(_ value: MPEG2NativeSession, id: UUID) -> Bool {
        guard generation == id else { value.cancel(); return false }
        session = value
        return true
    }
    private func isCurrent(_ id: UUID) -> Bool { generation == id }
    private func setAudioTracks(_ tracks: [AudioTrack], selected: Int, id: UUID) {
        guard generation == id else { return }
        availableAudioTracks = tracks; selectedAudioTrackID = selected >= 0 ? selected : nil
        if let preferredAudio, let match = tracks.first(where: {
            $0.isDecodable && $0.languageCode == preferredAudio.languageCode && $0.codec == preferredAudio.codec && $0.channels == preferredAudio.channels
        }), match.id != selectedAudioTrackID {
            selectedAudioTrackID = match.id
            if let session { cm2_request_audio(session.decoder, Int32(match.id)) }
        }
        buffers.expectsAudio = selected >= 0
    }
    private func restartNeeded(waitBegan: TimeInterval) -> Bool {
        pendingRestart || (desiredRate > 0 && ProcessInfo.processInfo.systemUptime - waitBegan > 8)
    }
    private func prepareTimestamp(_ decoded: MPEG2DecodedSample) {
        guard clockStarted else { return }
        let next = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(decoded.sample))
        let previous = decoded.kind == 1 ? lastVideoPTS : lastAudioPTS
        if LiveStreamRecoveryPolicy.isTimestampDiscontinuity(previous: previous, next: next) {
            timestampResets += 1
            resetOutputForRecovery()
        }
    }
    private func requestRecovery() {
        guard worker != nil, state != .stopped, state != .error, !pendingRestart else { return }
        pendingRestart = true; session?.cancel()
    }
    private func prepareRecovery(error: PlaybackError, recoverable: Bool, id: UUID) -> TimeInterval? {
        guard generation == id else { return nil }
        guard let delay = recovery.nextDelay(recoverable: recoverable || pendingRestart, now: ProcessInfo.processInfo.systemUptime) else {
            failed(error, id: id); return nil
        }
        session?.cancel(); session = nil; pendingRestart = false
        resetOutputForRecovery()
        lastProgress = ProcessInfo.processInfo.systemUptime
        isBuffering = desiredRate > 0; state = desiredRate == 0 ? .paused : .loading
        return delay
    }
    private func flushOutput() {
        synchronizer.rate = 0
        let flush = UUID(); flushID = flush; outputReady = false
        surface.display.sampleBufferRenderer.flush(removingDisplayedImage: true) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.flushID == flush else { return }
                self.outputReady = true
            }
        }
        audio.flush()
    }
    private func resetOutputForRecovery() {
        elapsedBeforeRecovery = currentTime
        flushOutput()
        let expectsAudio = buffers.expectsAudio
        buffers = LivePlaybackBufferState(); buffers.expectsAudio = expectsAudio
        origin = nil; clockStarted = false; lastAudioPTS = nil; lastVideoPTS = nil
    }
    private func ready(_ decoded: MPEG2DecodedSample) -> Bool {
        if decoded.kind == 2 && decoded.audioTrackID != selectedAudioTrackID { return true }
        guard outputReady else { return false }
        if origin != nil {
            let ahead = CMTimeGetSeconds(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(decoded.sample), synchronizer.currentTime()))
            if ahead > (clockStarted ? 0.6 : 2) { return false }
        }
        return decoded.kind == 1 ? surface.display.sampleBufferRenderer.isReadyForMoreMediaData : audio.isReadyForMoreMediaData
    }
    private func enqueue(_ decoded: MPEG2DecodedSample, id: UUID) {
        guard generation == id else { return }
        if decoded.kind == 2 && decoded.audioTrackID != selectedAudioTrackID { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(decoded.sample)
        lastProgress = ProcessInfo.processInfo.systemUptime
        recovery.markHealthy(now: lastProgress)
        if origin == nil || (!clockStarted && CMTimeCompare(pts, origin!) < 0) {
            origin = pts
            synchronizer.setRate(0, time: pts)
        }
        if decoded.kind == 1 {
            submittedVideoFrames += 1
            // A late submission is observable here; actual display drops are not.
            if clockStarted && desiredRate > 0 && CMTimeCompare(pts, synchronizer.currentTime()) < 0 {
                lateVideoSubmissions += 1
            }
            if let pixel = CMSampleBufferGetImageBuffer(decoded.sample) {
                outputVideoWidth = CVPixelBufferGetWidth(pixel)
                outputVideoHeight = CVPixelBufferGetHeight(pixel)
            }
            if let previous = lastVideoPTS {
                let interval = CMTimeGetSeconds(pts) - previous
                if interval.isFinite && interval > 0 && interval < 0.5 { outputVideoCadence = 1 / interval }
            }
            lastVideoPTS = CMTimeGetSeconds(pts)
            surface.display.sampleBufferRenderer.enqueue(decoded.sample)
            buffers.enqueueVideo(end: CMTimeGetSeconds(pts))
        } else {
            if let description = CMSampleBufferGetFormatDescription(decoded.sample),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description) {
                outputAudioChannels = Int(asbd.pointee.mChannelsPerFrame)
                outputAudioRate = asbd.pointee.mSampleRate
            }
            lastAudioPTS = CMTimeGetSeconds(pts)
            audio.enqueue(decoded.sample)
            let duration = CMSampleBufferGetDuration(decoded.sample)
            let end = CMTimeGetSeconds(pts) + max(0, CMTimeGetSeconds(duration))
            buffers.enqueueAudio(end: end)
        }
        gpuBlocks = decoded.blocks; gpuSeconds = decoded.gpuSeconds
        startClockIfReady()
    }
    private func startClockIfReady() {
        guard let origin else { return }
        if !clockStarted && buffers.canStart(at: CMTimeGetSeconds(origin)) {
            clockStarted = true
            synchronizer.setRate(desiredRate, time: origin)
        }
        isBuffering = !clockStarted && desiredRate > 0
        state = desiredRate == 0 ? .paused : clockStarted ? .playing : .loading
    }
    private func updateClock() {
        if let origin {
            buffers.observe(time: CMTimeGetSeconds(synchronizer.currentTime()), running: clockStarted && desiredRate > 0)
            currentTime = elapsedBeforeRecovery + max(0, CMTimeGetSeconds(CMTimeSubtract(synchronizer.currentTime(), origin)))
        }
        if surface.display.sampleBufferRenderer.status == .failed || audio.status == .failed {
            requestRecovery()
        }
        if desiredRate > 0 && ProcessInfo.processInfo.systemUptime - lastProgress > 8 { requestRecovery() }
    }
    private func failed(_ error: PlaybackError, id: UUID) {
        guard generation == id else { return }
        worker?.cancel(); session?.cancel()
        synchronizer.rate = 0; isBuffering = false; self.error = error; state = .error
    }
    func stop() {
        generation = UUID(); worker?.cancel(); session?.cancel(); worker = nil; session = nil
        timer?.invalidate(); timer = nil
        flushOutput()
        origin = nil; clockStarted = false; buffers = LivePlaybackBufferState()
        elapsedBeforeRecovery = 0; pendingRestart = false; pauseBegan = nil
        lastAudioPTS = nil; lastVideoPTS = nil; preferredAudio = nil
        recovery = LiveStreamRecoveryPolicy(); timestampResets = 0
        currentTime = 0; gpuBlocks = 0; gpuSeconds = 0
        submittedVideoFrames = 0; lateVideoSubmissions = 0
        outputVideoWidth = 0; outputVideoHeight = 0; outputVideoCadence = 0
        availableAudioTracks = []; selectedAudioTrackID = nil; outputAudioChannels = 0; outputAudioRate = 0
        isBuffering = false; state = .stopped
    }
    func play() {
        guard worker != nil, state != .stopped, state != .error else { return }
        if LiveStreamRecoveryPolicy.shouldRefreshAfterPause(began: pauseBegan, now: ProcessInfo.processInfo.systemUptime) { requestRecovery() }
        pauseBegan = nil; desiredRate = 1
        if clockStarted && !pendingRestart { synchronizer.rate = 1; state = .playing } else { startClockIfReady() }
    }
    func pause() {
        guard worker != nil, state != .stopped, state != .error else { return }
        if desiredRate > 0 { pauseBegan = ProcessInfo.processInfo.systemUptime }
        desiredRate = 0; synchronizer.rate = 0; state = .paused
    }
    func setPlaybackRate(_ rate: Float) { desiredRate = rate; if clockStarted { synchronizer.rate = rate } }
    func seek(to position: TimeInterval) {
        // The experimental renderer has no DVR seek mapping. Do not pretend that
        // a seek changed the stream or restart a second Plex tuner session.
    }
    func recoverFromStall() { requestRecovery() }
    func handleReturnToForeground() { surface.needsLayout = true; if desiredRate > 0 { requestRecovery() } }
    func configureVideoEnhancement(_ request: VideoEnhancementRequest) {}
    func configureCoordinatedPlayback(itemIdentifier: String?) {}
    func selectSubtitleTrack(_ track: SubtitleTrack?) {}
    func selectAudioTrack(_ track: AudioTrack) {
        guard let session, track.isDecodable,
              availableAudioTracks.contains(where: { $0.id == track.id && $0.isDecodable }),
              selectedAudioTrackID != track.id else { return }
        preferredAudio = track
        selectedAudioTrackID = track.id
        audio.flush(); buffers.resetAudio()
        cm2_request_audio(session.decoder, Int32(track.id))
    }
    func setVideoFillEnabled(_ enabled: Bool) { surface.display.videoGravity = enabled ? .resizeAspectFill : .resizeAspect }
    func makePlayerView() -> AnyView { AnyView(MPEG2SurfaceHost(view: surface)) }
    private var queueEndOffset: String {
        guard let audioEnd = buffers.audioEnd, let videoEnd = buffers.videoEnd else { return "Unavailable" }
        return String(format: "%.3f s", audioEnd - videoEnd)
    }
    var renderingDiagnostics: [(String, String)] {
        [("Decoder", mode == .metal ? "FFmpeg + Metal IDCT (experimental)" : "FFmpeg CPU (experimental)"),
         ("GPU reconstructed blocks", String(gpuBlocks)),
         ("GPU reconstruction time", String(format: "%.3f s", gpuSeconds)),
         ("Prediction / parsing", "CPU"),
         ("Stream reconnects", String(recovery.totalAttempts)),
         ("Timestamp resets", String(timestampResets)),
         ("Video output", "\(outputVideoWidth) × \(outputVideoHeight) · " + String(format: "%.2f outputs/s", outputVideoCadence)),
         ("Video submitted / late", "\(submittedVideoFrames) / \(lateVideoSubmissions) (not display drops)"),
         ("Audio", "\(outputAudioChannels) ch PCM · \(Int(outputAudioRate)) Hz"),
         ("Video processing", "BWDIF field-rate deinterlacing; progressive passthrough"),
         ("Audio queued", String(format: "%.3f s", buffers.audioDepth(at: CMTimeGetSeconds(synchronizer.currentTime())))),
         ("Video queued", String(format: "%.3f s", buffers.videoDepth(at: CMTimeGetSeconds(synchronizer.currentTime())))),
         ("Peak queued A/V (current context)", String(format: "%.3f / %.3f s", buffers.peakAudioDepth, buffers.peakVideoDepth)),
         ("Queue-end A−V (not measured sync drift)", queueEndOffset),
         ("Observed video buffer starvations", String(buffers.videoStarvations)),
         ("Observed audio buffer starvations", String(buffers.audioStarvations)),
         ("Prototype limits", "No captions; live playback only")]
    }
}

@MainActor private final class MPEG2VideoSurface: NSView {
    let display = AVSampleBufferDisplayLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        display.videoGravity = .resizeAspect; layer?.addSublayer(display)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); display.frame = bounds }
}
private struct MPEG2SurfaceHost: NSViewRepresentable {
    let view: MPEG2VideoSurface
    func makeNSView(context: Context) -> MPEG2VideoSurface { view }
    func updateNSView(_ view: MPEG2VideoSurface, context: Context) {}
}
extension ExperimentalMPEG2Engine: AVPlaybackCoordinatorPlaybackControlDelegate {
    nonisolated func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorPlayCommand, completionHandler: @escaping @Sendable () -> Void) {
        Task { @MainActor [weak self] in self?.play(); completionHandler() }
    }
    nonisolated func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorPauseCommand, completionHandler: @escaping @Sendable () -> Void) {
        Task { @MainActor [weak self] in self?.pause(); completionHandler() }
    }
    nonisolated func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorSeekCommand, completionHandler: @escaping @Sendable () -> Void) { completionHandler() }
    nonisolated func playbackCoordinator(_ coordinator: AVDelegatingPlaybackCoordinator, didIssue command: AVDelegatingPlaybackCoordinatorBufferingCommand, completionHandler: @escaping @Sendable () -> Void) { completionHandler() }
}
