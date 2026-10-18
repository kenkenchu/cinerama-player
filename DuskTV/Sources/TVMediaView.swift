import SwiftUI

@MainActor
@Observable
final class TVMediaModel {
    var details: PlexMediaDetails?
    var seasons: [PlexSeason] = []
    var episodes: [PlexEpisode] = []
    var message: String?
    var busy = false

    func load(service: PlexService, id: PlexItemID) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let value = try await service.getMediaDetails(ratingKey: id.ratingKey, serverID: id.serverID)
            try Task.checkCancellation()
            details = value
            if value.type == .show {
                seasons = try await service.getSeasons(showKey: id.ratingKey, serverID: id.serverID)
            } else if value.type == .season {
                episodes = try await service.getEpisodes(seasonKey: id.ratingKey, serverID: id.serverID)
            }
        } catch is CancellationError {
        } catch { message = "Could not load this title. Check the server connection and retry." }
    }
}

struct TVMediaView: View {
    let service: PlexService
    let itemID: PlexItemID
    @State private var model = TVMediaModel()
    @State private var presentation: TVPlayerPresentation?
    @State private var lastPlayback: TVPlaybackCoordinator?
    @State private var subtitleSelections: [Int: Int] = [:]

    var body: some View {
        List {
            if let details = model.details {
                Section {
                    if let series = details.grandparentTitle { Text(series).font(.title2) }
                    if let summary = details.summary { Text(summary).font(.body).foregroundStyle(.secondary) }
                }
                if details.type == .show {
                    Section("Seasons") {
                        ForEach(model.seasons) { season in
                            NavigationLink(season.title) {
                                TVMediaView(service: service, itemID: season.id)
                            }
                        }
                    }
                } else if details.type == .season {
                    Section("Episodes") {
                        ForEach(model.episodes) { episode in
                            NavigationLink {
                                TVMediaView(service: service, itemID: episode.id)
                            } label: {
                                TVItemLabel(title: episode.title,
                                    subtitle: episode.index.map { "Episode \($0)" })
                            }
                        }
                    }
                } else {
                    Section("Play an HD version") {
                        ForEach(Array(details.media.enumerated()), id: \.offset) { index, media in
                            versionRow(details: details, media: media, index: index)
                        }
                        if details.media.isEmpty { Text("Plex has no playable media file for this title.") }
                    }
                    if let lastPlayback {
                        Section("Last playback") {
                            Text(lastPlayback.route)
                            Text(lastPlayback.subtitleMessage)
                            if let summary = lastPlayback.nativeSubtitleSummary { Text(summary) }
                            if let progress = lastPlayback.progressMessage { Text(progress) }
                            if let error = lastPlayback.errorMessage { Text(error) }
                        }
                    }
                    Section {
                        Text("Native AVPlayer · Original quality only. Choose a text subtitle before playing; Plex packages it separately while copying video and audio. Bitmap subtitles, VLC, Live TV and automatic next episode are not in this prototype.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if model.busy { ProgressView("Loading title…") }
            if let message = model.message {
                Text(message)
                Button("Retry") { Task { await model.load(service: service, id: itemID) } }
            }
        }
        .navigationTitle(model.details?.title ?? "Loading…")
        .task { await model.load(service: service, id: itemID) }
        .fullScreenCover(item: $presentation, onDismiss: {
            Task { await model.load(service: service, id: itemID) }
        }) { session in
            TVPlayerScreen(playback: session.playback)
        }
    }

    @ViewBuilder
    private func versionRow(details: PlexMediaDetails, media: PlexMedia, index: Int) -> some View {
        if let choice = try? TVStreamResolver.choice(media: media, index: index,
            subtitleID: selectedSubtitle(media: media, index: index)) {
            let tracks = choice.part.streams.filter { $0.streamType == .subtitle }
            if tracks.isEmpty {
                Text("Version \(index + 1): Plex reports no subtitle tracks.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Subtitles · Version \(index + 1)", selection: Binding(
                    get: { selectedSubtitle(media: media, index: index) ?? 0 },
                    set: { subtitleSelections[index] = $0 }
                )) {
                    Text("Off").tag(0)
                    ForEach(tracks.filter(TVStreamResolver.supportsSubtitle)) { track in
                        Text("\(track.displayTitle ?? track.language ?? "Subtitle \(track.id)") · \(track.codec?.uppercased() ?? "Unknown format")")
                            .tag(track.id)
                    }
                }
                ForEach(tracks.filter { !TVStreamResolver.supportsSubtitle($0) }) { track in
                    Text("\(track.displayTitle ?? track.codec ?? "Subtitle"): unsupported format; choose a text track.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if (details.viewOffset ?? 0) > 0 {
                Button("Resume · \(choice.label)") { play(details: details, choice: choice, resume: true) }
            }
            Button("Play from Start · \(choice.label)") { play(details: details, choice: choice, resume: false) }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Version \(index + 1) · \(media.videoResolution ?? "Unknown resolution") · \(media.videoCodec ?? "Unknown codec")")
                Text(unsupportedReason(media: media, index: index)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func selectedSubtitle(media: PlexMedia, index: Int) -> Int? {
        if let selected = subtitleSelections[index] { return selected == 0 ? nil : selected }
        return media.parts.first?.streams.first {
            $0.isSelected == true && TVStreamResolver.supportsSubtitle($0)
        }?.id
    }

    private func unsupportedReason(media: PlexMedia, index: Int) -> String {
        do { _ = try TVStreamResolver.choice(media: media, index: index); return "" }
        catch { return (error as? TVPlaybackFailure)?.errorDescription ?? "Unsupported media version." }
    }

    private func play(details: PlexMediaDetails, choice: TVPlaybackChoice, resume: Bool) {
        let playback = TVPlaybackCoordinator(service: service, details: details, choice: choice, resume: resume)
        lastPlayback = playback
        presentation = TVPlayerPresentation(playback: playback)
    }
}

struct TVPlayerPresentation: Identifiable {
    let id = UUID()
    let playback: TVPlaybackCoordinator
}
