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
        let session = service.serverSessionToken
        message = nil
        defer { busy = false }
        do {
            let value = try await service.getMediaDetails(ratingKey: id.ratingKey, serverID: id.serverID)
            try Task.checkCancellation()
            guard session == service.serverSessionToken else { return }
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
    @State private var audioSelections: [Int: Int] = [:]

    var body: some View {
        List {
            if let details = model.details {
                Section {
                    GeometryReader { geometry in
                        ZStack(alignment: .bottomLeading) {
                            TVArtwork(service: service, path: details.art ?? details.thumb,
                                serverID: details.serverID, width: geometry.size.width,
                                height: geometry.size.height, cornerRadius: 28, showsPlaceholder: false)
                                .overlay {
                                    LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.5), .clear],
                                        startPoint: .leading, endPoint: .trailing)
                                }
                            VStack(alignment: .leading, spacing: 20) {
                                Text("CINERAMA / LIBRARY")
                                    .font(.system(.caption, design: .monospaced)).tracking(3)
                                    .foregroundStyle(.white.opacity(0.65))
                                if let series = details.grandparentTitle { Text(series).font(.title2) }
                                Text(details.title).font(.title.bold()).lineLimit(2)
                                if let year = details.year { Text(String(year)).foregroundStyle(.white.opacity(0.7)) }
                                if let summary = details.summary {
                                    Text(summary).font(.body).foregroundStyle(.white.opacity(0.85)).lineLimit(4)
                                }
                            }
                            .frame(maxWidth: 900, alignment: .leading).padding(48)
                        }
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: 28))
                        .overlay { TVViewportEdge() }
                    }.frame(height: 540).padding(.vertical, 20)
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
                        Section {
                            NavigationLink("Playback Information") {
                                List {
                                    Text(lastPlayback.route)
                                    Text(lastPlayback.subtitleMessage)
                                    if let summary = lastPlayback.nativeSubtitleSummary { Text(summary) }
                                    if let progress = lastPlayback.progressMessage { Text(progress) }
                                    if let error = lastPlayback.errorMessage { Text(error) }
                                }.navigationTitle("Playback Information")
                            }
                        }
                    }
                    Section {
                        Text("Choose audio and subtitles before playing. Your choices are remembered for this movie or series. Some subtitle and audio formats are not supported on Apple TV HD yet.")
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
        .background { TVDeckBackground().ignoresSafeArea() }
        .navigationTitle(model.details?.title ?? "Loading…")
        .task { await model.load(service: service, id: itemID) }
        .fullScreenCover(item: $presentation, onDismiss: {
            Task {
                let session = service.serverSessionToken
                await lastPlayback?.finish()
                guard session == service.serverSessionToken else { return }
                await model.load(service: service, id: itemID)
                NotificationCenter.default.post(name: .tvCatalogNeedsRefresh, object: nil)
            }
        }) { session in
            TVPlayerScreen(playback: session.playback)
        }
    }

    @ViewBuilder
    private func versionRow(details: PlexMediaDetails, media: PlexMedia, index: Int) -> some View {
        if let choice = try? TVStreamResolver.choice(media: media, index: index,
            subtitleID: selectedSubtitle(media: media, index: index),
            audioID: selectedAudio(media: media, index: index)) {
            let audioTracks = choice.part.streams.filter { $0.streamType == .audio }
            if !audioTracks.isEmpty {
                Picker("Audio · Version \(index + 1)", selection: Binding(
                    get: { selectedAudio(media: media, index: index) ?? choice.audio?.id ?? 0 },
                    set: { id in
                        audioSelections[index] = id
                        TVTrackPreferences.remember(audioTracks.first { $0.id == id }, kind: "audio",
                            details: details, profile: service.activeProfileID)
                    }
                )) {
                    ForEach(audioTracks.filter(TVStreamResolver.supportsAudio)) { track in
                        Text(track.displayTitle ?? track.language ?? track.codec ?? "Audio").tag(track.id)
                    }
                }
                ForEach(audioTracks.filter { !TVStreamResolver.supportsAudio($0) }) { track in
                    Text("\(track.displayTitle ?? track.codec ?? "Audio"): unsupported on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            let tracks = choice.part.streams.filter { $0.streamType == .subtitle }
            if tracks.isEmpty {
                Text("Version \(index + 1): Plex reports no subtitle tracks.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Subtitles · Version \(index + 1)", selection: Binding(
                    get: { selectedSubtitle(media: media, index: index) ?? 0 },
                    set: { id in
                        subtitleSelections[index] = id
                        TVTrackPreferences.remember(tracks.first { $0.id == id }, kind: "subtitle",
                            details: details, profile: service.activeProfileID)
                    }
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
                    .modifier(TVDeckActionStyle(prominent: true))
            }
            Button("Play from Start · \(choice.label)") { play(details: details, choice: choice, resume: false) }
                .modifier(TVDeckActionStyle())
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Version \(index + 1) · \(media.videoResolution ?? "Unknown resolution") · \(media.videoCodec ?? "Unknown codec")")
                Text(unsupportedReason(media: media, index: index)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func selectedSubtitle(media: PlexMedia, index: Int) -> Int? {
        if let selected = subtitleSelections[index] {
            return media.parts.first?.streams.contains(where: {
                $0.id == selected && TVStreamResolver.supportsSubtitle($0)
            }) == true ? selected : nil
        }
        let tracks = media.parts.first?.streams.filter(TVStreamResolver.supportsSubtitle) ?? []
        if let details = model.details,
           let saved = TVTrackPreferences.selection(kind: "subtitle", streams: tracks,
               details: details, profile: service.activeProfileID) { return saved }
        return media.parts.first?.streams.first {
            $0.isSelected == true && TVStreamResolver.supportsSubtitle($0)
        }?.id
    }

    private func selectedAudio(media: PlexMedia, index: Int) -> Int? {
        if let id = audioSelections[index], media.parts.first?.streams.contains(where: {
            $0.id == id && TVStreamResolver.supportsAudio($0)
        }) == true { return id }
        guard let details = model.details else { return nil }
        let tracks = media.parts.first?.streams.filter(TVStreamResolver.supportsAudio) ?? []
        if let saved = TVTrackPreferences.selection(kind: "audio", streams: tracks,
            details: details, profile: service.activeProfileID) { return saved }
        return nil
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
