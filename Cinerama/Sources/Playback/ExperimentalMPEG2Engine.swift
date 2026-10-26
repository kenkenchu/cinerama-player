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
    var failure: PlaybackError { .unknown(String(cString: cm2_error(decoder))) }
    func next() throws -> MPEG2DecodedSample? {
        var kind: Int32 = 0
        guard let sample = cm2_next(decoder, &kind) else {
            if kind < 0 { throw failure }
            return nil
        }
        return .init(sample: sample, kind: kind, blocks: cm2_gpu_blocks(decoder), gpuSeconds: cm2_gpu_seconds(decoder))
    }
}
private struct MPEG2DecodedSample: @unchecked Sendable {
    let sample: CMSampleBuffer
    let kind: Int32
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
    var seekableTimeRange: ClosedRange<TimeInterval>? { nil }
    private(set) var isBuffering = false
    private(set) var error: PlaybackError?
    var availableSubtitleTracks: [SubtitleTrack] { [] }
    var availableAudioTracks: [AudioTrack] { [] }
    var selectedSubtitleTrackID: Int? { nil }
    var selectedAudioTrackID: Int? { nil }
    var prefersSpatializedAudioSession: Bool { false }
    var videoEnhancementStatus: VideoEnhancementStatus { .init(state: .unavailable, reason: "Experimental MPEG-2 renderer") }
    var onPlaybackEnded: (@MainActor () -> Void)?
    var playbackCoordinator: AVPlaybackCoordinator { coordinator }
    let mode: ExperimentalMPEG2Mode
    private(set) var gpuBlocks: UInt64 = 0
    private(set) var gpuSeconds = 0.0
    private(set) var buffers = LivePlaybackBufferState()
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

    init(mode: ExperimentalMPEG2Mode) {
        self.mode = mode
        super.init()
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        synchronizer.addRenderer(surface.display.sampleBufferRenderer)
        synchronizer.addRenderer(audio)
        coordinator = AVDelegatingPlaybackCoordinator(playbackControlDelegate: self)
    }
    deinit { worker?.cancel(); session?.cancel(); timer?.invalidate() }

    func load(source: PlaybackSource) {
        stop()
        let id = UUID(); generation = id
        state = .loading; isBuffering = true; error = nil
        desiredRate = source.shouldAutoPlay ? 1 : 0
        let mode = mode
        worker = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let session = try MPEG2NativeSession(metal: mode == .metal)
                guard let self, await self.attach(session, id: id) else { return }
                try session.open(source.url)
                await self.setAudioExpectation(cm2_has_audio(session.decoder) != 0, id: id)
                while !Task.isCancelled, let decoded = try session.next() {
                    while !Task.isCancelled {
                        guard await self.isCurrent(id) else { return }
                        if await self.ready(decoded) { break }
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    try Task.checkCancellation()
                    await self.enqueue(decoded, id: id)
                }
                await self.finished(id: id)
            } catch is CancellationError {
                // Retirement is deliberate and cannot update a newer session.
            } catch {
                await self?.failed(error as? PlaybackError ?? .unknown("Experimental MPEG-2 playback failed."), id: id)
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
    private func setAudioExpectation(_ value: Bool, id: UUID) {
        guard generation == id else { return }
        buffers.expectsAudio = value
    }
    private func ready(_ decoded: MPEG2DecodedSample) -> Bool {
        guard outputReady else { return false }
        if origin != nil {
            let ahead = CMTimeGetSeconds(CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(decoded.sample), synchronizer.currentTime()))
            if ahead > (clockStarted ? 0.6 : 2) { return false }
        }
        return decoded.kind == 1 ? surface.display.sampleBufferRenderer.isReadyForMoreMediaData : audio.isReadyForMoreMediaData
    }
    private func enqueue(_ decoded: MPEG2DecodedSample, id: UUID) {
        guard generation == id else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(decoded.sample)
        if origin == nil || (!clockStarted && CMTimeCompare(pts, origin!) < 0) {
            origin = pts
            synchronizer.setRate(0, time: pts)
        }
        if decoded.kind == 1 {
            surface.display.sampleBufferRenderer.enqueue(decoded.sample)
            buffers.enqueueVideo(end: CMTimeGetSeconds(pts))
        } else {
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
            currentTime = max(0, CMTimeGetSeconds(CMTimeSubtract(synchronizer.currentTime(), origin)))
        }
        if surface.display.sampleBufferRenderer.status == .failed || audio.status == .failed {
            failed(.unknown("Experimental audio/video output failed. Select Standard playback and retune."), id: generation)
        }
    }
    private func failed(_ error: PlaybackError, id: UUID) {
        guard generation == id else { return }
        worker?.cancel(); session?.cancel()
        synchronizer.rate = 0; isBuffering = false; self.error = error; state = .error
    }
    private func finished(id: UUID) {
        guard generation == id else { return }
        failed(.unknown("The experimental Live TV stream ended. Select Standard playback and retune."), id: id)
    }
    func stop() {
        generation = UUID(); worker?.cancel(); session?.cancel(); worker = nil; session = nil
        timer?.invalidate(); timer = nil
        synchronizer.rate = 0
        let flush = UUID(); flushID = flush; outputReady = false
        surface.display.sampleBufferRenderer.flush(removingDisplayedImage: true) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.flushID == flush else { return }
                self.outputReady = true
            }
        }
        audio.flush()
        origin = nil; clockStarted = false; buffers = LivePlaybackBufferState()
        currentTime = 0; gpuBlocks = 0; gpuSeconds = 0
        isBuffering = false; state = .stopped
    }
    func play() { desiredRate = 1; if clockStarted { synchronizer.rate = 1; state = .playing } else { startClockIfReady() } }
    func pause() { desiredRate = 0; synchronizer.rate = 0; state = .paused }
    func setPlaybackRate(_ rate: Float) { desiredRate = rate; if clockStarted { synchronizer.rate = rate } }
    func seek(to position: TimeInterval) {
        // The experimental renderer has no DVR seek mapping. Do not pretend that
        // a seek changed the stream or restart a second Plex tuner session.
    }
    func recoverFromStall() { play() }
    func handleReturnToForeground() { surface.needsLayout = true }
    func configureVideoEnhancement(_ request: VideoEnhancementRequest) {}
    func configureCoordinatedPlayback(itemIdentifier: String?) {}
    func selectSubtitleTrack(_ track: SubtitleTrack?) {}
    func selectAudioTrack(_ track: AudioTrack) {}
    func setVideoFillEnabled(_ enabled: Bool) { surface.display.videoGravity = enabled ? .resizeAspectFill : .resizeAspect }
    func makePlayerView() -> AnyView { AnyView(MPEG2SurfaceHost(view: surface)) }
    var renderingDiagnostics: [(String, String)] {
        [("Decoder", mode == .metal ? "FFmpeg + Metal IDCT (experimental)" : "FFmpeg CPU (experimental)"),
         ("GPU reconstructed blocks", String(gpuBlocks)),
         ("GPU reconstruction time", String(format: "%.3f s", gpuSeconds)),
         ("Prediction / parsing", "CPU"),
         ("Audio", "Stereo PCM; default track"),
         ("Video processing", "BWDIF field-rate deinterlacing; progressive passthrough"),
         ("Audio queued", String(format: "%.3f s", buffers.audioDepth(at: CMTimeGetSeconds(synchronizer.currentTime())))),
         ("Video queued", String(format: "%.3f s", buffers.videoDepth(at: CMTimeGetSeconds(synchronizer.currentTime())))),
         ("Observed audio buffer starvations", String(buffers.audioStarvations)),
         ("Prototype limits", "No captions or track switching; live playback only")]
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
