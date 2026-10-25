import Foundation
import Testing
@testable import CineramaTV

@Suite("TV remembered audio and subtitles")
struct TVTrackPreferencesTests {
    @Test func explicitOffIsDifferentFromNoPreference() throws {
        try isolatedDefaults { defaults in
            let details = try TVTestFixtures.details()
            let streams = [try TVTestFixtures.stream(TVTestFixtures.subtitle)]
            #expect(TVTrackPreferences.selection(kind: "subtitle", streams: streams,
                details: details, profile: "profile", defaults: defaults) == nil)
            TVTrackPreferences.remember(nil, kind: "subtitle", details: details, profile: "profile", defaults: defaults)
            let saved = TVTrackPreferences.selection(kind: "subtitle", streams: streams,
                details: details, profile: "profile", defaults: defaults)
            let explicitChoice = try #require(saved)
            #expect(explicitChoice == nil)
        }
    }

    @Test func seriesChoicesMatchNewTrackIDsAcrossEpisodes() throws {
        try isolatedDefaults { defaults in
            let first = try TVTestFixtures.details(ratingKey: "episode1", type: "episode", series: "show1")
            let next = try TVTestFixtures.details(ratingKey: "episode2", type: "episode", series: "show1")
            let original = try TVTestFixtures.stream(TVTestFixtures.subtitle)
            TVTrackPreferences.remember(original, kind: "subtitle", details: first, profile: "profile", defaults: defaults)
            var newer = TVTestFixtures.subtitle
            newer["id"] = 99
            let streams = [try TVTestFixtures.stream(newer)]
            let selection = TVTrackPreferences.selection(kind: "subtitle", streams: streams,
                details: next, profile: "profile", defaults: defaults)
            #expect(selection == .some(.some(99)))
        }
    }

    @Test func choicesAreIsolatedByProfileServerMovieAndKind() throws {
        try isolatedDefaults { defaults in
            let original = try TVTestFixtures.details()
            let stream = try TVTestFixtures.stream(TVTestFixtures.audio)
            TVTrackPreferences.remember(stream, kind: "audio", details: original, profile: "profile1", defaults: defaults)
            func selection(_ details: PlexMediaDetails, profile: String, kind: String = "audio") -> Int?? {
                TVTrackPreferences.selection(kind: kind, streams: [stream], details: details,
                    profile: profile, defaults: defaults)
            }
            #expect(selection(original, profile: "profile1") == .some(.some(2)))
            #expect(selection(original, profile: "profile2") == nil)
            #expect(selection(try TVTestFixtures.details(server: "server-b"), profile: "profile1") == nil)
            #expect(selection(try TVTestFixtures.details(ratingKey: "2"), profile: "profile1") == nil)
            #expect(selection(original, profile: "profile1", kind: "subtitle") == nil)
        }
    }

    @Test func forcedAndHearingImpairedPreferencesDoNotSelectOrdinaryTracks() throws {
        try isolatedDefaults { defaults in
            let details = try TVTestFixtures.details()
            var saved = TVTestFixtures.subtitle
            saved["forced"] = true
            saved["hearingImpaired"] = true
            TVTrackPreferences.remember(try TVTestFixtures.stream(saved), kind: "subtitle", details: details,
                profile: "profile", defaults: defaults)
            var matching = saved
            matching["id"] = 5
            let streams = try [TVTestFixtures.subtitle, matching].map(TVTestFixtures.stream)
            #expect(TVTrackPreferences.selection(kind: "subtitle", streams: streams, details: details,
                profile: "profile", defaults: defaults) == .some(.some(5)))
        }
    }

    @Test func missingProfileServerOrSeriesDoesNotPersistAnUnscopedChoice() throws {
        try isolatedDefaults { defaults in
            let details = try TVTestFixtures.details()
            let unstamped = try TVTestFixtures.details(server: nil)
            let episode = try TVTestFixtures.details(type: "episode")
            for (item, profile) in [(details, nil as String?), (unstamped, "profile"), (episode, "profile")] {
                TVTrackPreferences.remember(nil, kind: "subtitle", details: item, profile: profile, defaults: defaults)
                #expect(TVTrackPreferences.selection(kind: "subtitle", streams: [], details: item,
                    profile: profile, defaults: defaults) == nil)
            }
        }
    }

    private func isolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "com.cinerama-player.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
