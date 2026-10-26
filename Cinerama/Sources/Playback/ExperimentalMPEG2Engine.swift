import AppKit
import AVFoundation
import SwiftUI

extension ExperimentalMPEG2Engine: PlaybackEngine {
    func load(source: PlaybackSource) { load(url: source.url, shouldAutoPlay: source.shouldAutoPlay) }
    var videoEnhancementStatus: VideoEnhancementStatus { .init(state: .unavailable, reason: "Experimental MPEG-2 renderer") }
    func handleReturnToForeground() {
        (renderingHost as? MPEG2VideoSurface)?.needsLayout = true
        recoverAfterForeground()
    }
    func configureVideoEnhancement(_ request: VideoEnhancementRequest) {}
    func makePlayerView() -> AnyView {
        let view = (renderingHost as? MPEG2VideoSurface) ?? MPEG2VideoSurface(display: display)
        renderingHost = view
        return AnyView(MPEG2SurfaceHost(view: view))
    }
}

@MainActor private final class MPEG2VideoSurface: NSView {
    let display: AVSampleBufferDisplayLayer
    init(display: AVSampleBufferDisplayLayer) {
        self.display = display
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        display.videoGravity = .resizeAspect; layer?.addSublayer(display)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); display.frame = bounds }
}
private struct MPEG2SurfaceHost: NSViewRepresentable {
    let view: MPEG2VideoSurface
    func makeNSView(context: Context) -> MPEG2VideoSurface { view }
    func updateNSView(_ view: MPEG2VideoSurface, context: Context) {}
}
