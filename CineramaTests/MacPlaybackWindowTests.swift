import AppKit
import SwiftUI
import Testing
@testable import Cinerama

@Suite("Mac playback window sequence")
struct MacPlaybackWindowTests {
    @Test func escapeExitsFullscreenWithoutDismissingPlayback() {
        var state = MacPlaybackWindowState()
        let transition1 = state.beginEntering()
        #expect(transition1)
        #expect(state.escapeAction(isRepeat: false) == .ignore)
        state.didEnter()
        #expect(state.escapeAction(isRepeat: false) == .exitFullscreen)
        let transition2 = state.beginExiting()
        #expect(transition2)
        #expect(state.escapeAction(isRepeat: false) == .ignore)
        state.didRestoreInline()
        #expect(state.phase == .inline)
        // The same held Escape must not become a second windowed Close.
        #expect(state.escapeAction(isRepeat: true) == .ignore)
        #expect(state.escapeAction(isRepeat: false) == .dismissPlayback)
    }

    @Test func repeatedFullscreenCommandsCannotStartOverlappingTransitions() {
        var state = MacPlaybackWindowState()
        let transition3 = state.beginEntering()
        #expect(transition3)
        let transition4 = state.beginEntering()
        #expect(!transition4)
        let transition5 = state.beginExiting()
        #expect(!transition5)
        state.didEnter()
        let transition6 = state.beginExiting()
        #expect(transition6)
        let transition7 = state.beginExiting()
        #expect(!transition7)
        let transition8 = state.beginEntering()
        #expect(!transition8)
        state.didRestoreInline()
        let transition9 = state.beginEntering()
        #expect(transition9)
    }

    @Test func failedEntryRestoresWindowedPlaybackAndCanRetry() {
        var state = MacPlaybackWindowState()
        let transition10 = state.beginEntering()
        #expect(transition10)
        state.didRestoreInline()
        #expect(state.phase == .inline)
        #expect(!state.isTransitioning)
        let transition11 = state.beginEntering()
        #expect(transition11)
        state.didEnter()
        #expect(state.phase == .fullscreen)
    }

    @Test func failedExitRetainsFullscreenAndCanRetry() {
        var state = MacPlaybackWindowState()
        let transition12 = state.beginEntering()
        #expect(transition12)
        state.didEnter()
        let transition13 = state.beginExiting()
        #expect(transition13)
        state.failedToExit()
        #expect(state.phase == .fullscreen)
        #expect(state.escapeAction(isRepeat: false) == .exitFullscreen)
        let transition14 = state.beginExiting()
        #expect(transition14)
        state.didRestoreInline()
        #expect(state.phase == .inline)
    }

    @Test func nativeExitAndMultipleRoundTripsKeepThePlayerPresent() {
        var state = MacPlaybackWindowState()
        for _ in 0..<10 {
            let transition15 = state.beginEntering()
            #expect(transition15)
            state.didEnter()
            // Native green-button/Space transition uses the same delegate path.
            let transition16 = state.beginExiting()
            #expect(transition16)
            state.didRestoreInline()
            #expect(state.phase == .inline)
            #expect(!state.isTransitioning)
        }
    }

    @Test(arguments: [MacPlaybackWindowState.Phase.inline, .enteringFullscreen, .fullscreen, .exitingFullscreen])
    func closingInvalidatesOutstandingWindowCallbacks(phase: MacPlaybackWindowState.Phase) {
        var state = MacPlaybackWindowState()
        if phase != .inline { _ = state.beginEntering() }
        if phase == .fullscreen || phase == .exitingFullscreen { state.didEnter() }
        if phase == .exitingFullscreen { _ = state.beginExiting() }
        state.close()
        state.didEnter()
        state.didRestoreInline()
        state.failedToExit()
        #expect(state.phase == .closed)
        #expect(state.escapeAction(isRepeat: false) == .ignore)
        let transition17 = state.beginEntering()
        #expect(!transition17)
        let transition18 = state.beginExiting()
        #expect(!transition18)
    }

    @Test func resumeAfterDismissalStartsWithFreshWindowState() {
        var outgoing = MacPlaybackWindowState()
        let transition19 = outgoing.beginEntering()
        #expect(transition19)
        outgoing.didEnter()
        outgoing.close()
        let resumed = MacPlaybackWindowState()
        // Late notifications affect only the retired presentation.
        outgoing.didRestoreInline()
        #expect(outgoing.phase == .closed)
        #expect(resumed.phase == .inline)
        #expect(resumed.escapeAction(isRepeat: false) == .dismissPlayback)
    }
}

@Suite("Mac playback host attachment", .serialized)
@MainActor
struct MacPlaybackHostAttachmentTests {
    @Test func windowTransferReusesOneHostAndRepairsInlineAttachment() throws {
        let playback = PlaybackCoordinator(plexService: PlexService())
        let coordinator = MacPlaybackHost.Coordinator(playback: playback, detached: .constant(false))
        defer { coordinator.tearDown() }
        let original = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        coordinator.updateContainer(original)
        let host = try #require(original.subviews.first)
        let fullscreen = NSView(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        coordinator.attachPlayer(to: fullscreen)
        #expect(original.subviews.isEmpty)
        #expect(fullscreen.subviews.first === host)
        #expect(host.frame == fullscreen.bounds)
        // SwiftUI supplied a replacement inline container during the transfer.
        let replacement = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        coordinator.updateContainer(replacement)
        #expect(fullscreen.subviews.isEmpty)
        #expect(replacement.subviews.first === host)
        #expect(host.frame == replacement.bounds)
        coordinator.updateContainer(replacement)
        #expect(replacement.subviews.count == 1)
    }

    @Test func retiredHostCannotStealOrRemoveTheResumedPlayer() throws {
        let playback = PlaybackCoordinator(plexService: PlexService())
        let inline = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let outgoing = MacPlaybackHost.Coordinator(playback: playback, detached: .constant(false))
        outgoing.updateContainer(inline)
        let previousHost = try #require(inline.subviews.first)
        outgoing.tearDown()
        #expect(inline.subviews.isEmpty)
        let resumed = MacPlaybackHost.Coordinator(playback: playback, detached: .constant(false))
        defer { resumed.tearDown() }
        resumed.updateContainer(inline)
        let newHost = try #require(inline.subviews.first)
        #expect(newHost !== previousHost)
        outgoing.attachPlayer(to: inline)
        outgoing.updateContainer(inline)
        outgoing.tearDown()
        #expect(inline.subviews.count == 1)
        #expect(inline.subviews.first === newHost)
    }
}
