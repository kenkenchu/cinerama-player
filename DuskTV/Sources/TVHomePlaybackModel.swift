import Foundation

/// Home's direct Play/Resume action. The modal is above the Home navigation
/// stack, so closing it restores the catalog and its remote focus context.
@MainActor
@Observable
final class TVHomePlaybackModel {
    var presentation: TVPlayerPresentation?
    private(set) var lastPlayback: TVPlaybackCoordinator?
    private(set) var isPreparing = false
    var awaitsFinalization = false
    var message: String?
    private var generation = UUID()

    func play(_ item: PlexItem, service: PlexService) async {
        guard !isPreparing, presentation == nil else { return }
        let attempt = UUID()
        generation = attempt
        let session = service.serverSessionToken
        isPreparing = true
        message = nil
        defer { if generation == attempt { isPreparing = false } }
        do {
            var details = try await service.getMediaDetails(ratingKey: item.ratingKey,
                checkFiles: true, serverID: item.serverID)
            guard generation == attempt, session == service.serverSessionToken else { return }
            // PMS normally supplies an episode in Continue Watching. Resolve a
            // show/season defensively instead of treating it as a media file.
            if details.type == .show || details.type == .season {
                let episodes: [PlexEpisode]
                if details.type == .show {
                    episodes = try await service.getAllEpisodes(showKey: details.ratingKey, serverID: details.serverID)
                } else {
                    episodes = try await service.getEpisodes(seasonKey: details.ratingKey, serverID: details.serverID)
                }
                guard generation == attempt, session == service.serverSessionToken else { return }
                guard let episode = episodes.first(where: { ($0.viewOffset ?? 0) > 0 })
                    ?? episodes.first(where: { ($0.viewCount ?? 0) == 0 }) ?? episodes.first else {
                    throw TVPlaybackFailure.unsupported("No episode is available to play.")
                }
                details = try await service.getMediaDetails(ratingKey: episode.ratingKey,
                    checkFiles: true, serverID: episode.serverID)
            }
            guard generation == attempt, session == service.serverSessionToken else { return }
            let choice = try TVStreamResolver.preferredChoice(details: details, profile: service.activeProfileID)
            let playback = TVPlaybackCoordinator(service: service, details: details, choice: choice, resume: true)
            lastPlayback = playback
            awaitsFinalization = true
            presentation = TVPlayerPresentation(playback: playback)
        } catch is CancellationError {
        } catch {
            guard generation == attempt, session == service.serverSessionToken else { return }
            message = (error as? TVPlaybackFailure)?.errorDescription
                ?? "This title could not be opened. Check its Plex server, or open Details to choose another version."
        }
    }

    func cancelPreparation() {
        generation = UUID()
        isPreparing = false
    }
}

extension TVStreamResolver {
    static func preferredChoice(details: PlexMediaDetails, profile: String?) throws -> TVPlaybackChoice {
        var firstFailure: Error?
        for (index, media) in details.media.enumerated() {
            let streams = media.parts.first?.streams ?? []
            let subtitles = streams.filter(supportsSubtitle)
            let audio = streams.filter(supportsAudio)
            let savedSubtitle = TVTrackPreferences.selection(kind: "subtitle", streams: subtitles, details: details, profile: profile)
            let subtitleID: Int?
            if let savedSubtitle { subtitleID = savedSubtitle }
            else { subtitleID = subtitles.first { $0.isSelected == true }?.id }
            let audioID = TVTrackPreferences.selection(kind: "audio", streams: audio,
                details: details, profile: profile) ?? nil
            do { return try choice(media: media, index: index, subtitleID: subtitleID, audioID: audioID) }
            catch { firstFailure = firstFailure ?? error }
        }
        throw firstFailure ?? TVPlaybackFailure.unsupported("Plex has no available media version for this title.")
    }
}
