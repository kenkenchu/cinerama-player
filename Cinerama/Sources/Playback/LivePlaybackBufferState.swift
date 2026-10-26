import Foundation

/// Media-time queue observations, not hardware underrun/drop measurements.
/// Kept independent of AVFoundation so startup and starvation transitions can
/// be tested without launching a player or selecting an audio output device.
struct LivePlaybackBufferState {
    var expectsAudio = true
    private(set) var audioEnd: TimeInterval?
    private(set) var videoEnd: TimeInterval?
    private(set) var audioStarvations = 0
    private var wasAudioStarved = false

    mutating func enqueueAudio(end: TimeInterval) { audioEnd = max(audioEnd ?? end, end) }
    mutating func enqueueVideo(end: TimeInterval) { videoEnd = max(videoEnd ?? end, end) }
    func audioDepth(at time: TimeInterval) -> TimeInterval { max(0, (audioEnd ?? time) - time) }
    func videoDepth(at time: TimeInterval) -> TimeInterval { max(0, (videoEnd ?? time) - time) }
    func canStart(at time: TimeInterval) -> Bool {
        videoDepth(at: time) >= 0.1 && (!expectsAudio || audioDepth(at: time) >= 0.2)
    }
    mutating func observe(time: TimeInterval, running: Bool) {
        let starved = running && expectsAudio && audioEnd != nil && audioDepth(at: time) <= 0
        if starved && !wasAudioStarved { audioStarvations += 1 }
        wasAudioStarved = starved
    }
}
