import SwiftUI

struct TVLiveTVView: View {
    let service: PlexService
    @State private var model: LiveTVViewModel
    @State private var query = ""
    @State private var presentation: TVLivePlayerPresentation?
    @State private var lastPlayback: TVLivePlayback?

    init(service: PlexService) {
        self.service = service
        _model = State(initialValue: LiveTVViewModel(plexService: service))
    }

    private var visibleChannels: [PlexLiveChannel] {
        model.channels.filter {
            query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query)
                || ($0.displayNumber ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 32) {
                    TVDeckSectionHeading(title: "Live TV", subtitle: "Choose a channel to watch live")
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await model.load(force: true) }
                    }.modifier(TVDeckActionStyle()).disabled(model.isLoading)
                }
                if model.isLoading { ProgressView("Loading channels…") }
                if model.error != nil {
                    ContentUnavailableView("Channels unavailable", systemImage: "network.slash",
                        description: Text("Check your Plex server connection, then refresh."))
                }
                if !model.isLoading && model.channels.isEmpty && model.error == nil {
                    ContentUnavailableView("No channels available", systemImage: "tv",
                        description: Text("No Live TV channels are available from your Plex server."))
                } else if !query.isEmpty && visibleChannels.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: TVDeckLayout.cardSpacing)], spacing: 40) {
                    ForEach(visibleChannels) { channel in
                        Button {
                            guard let provider = model.provider else { return }
                            let playback = TVLivePlayback(service: service)
                            lastPlayback = playback
                            presentation = TVLivePlayerPresentation(provider: provider, channel: channel,
                                serverID: model.serverID, playback: playback)
                        } label: {
                            VStack(spacing: 12) {
                                TVArtwork(service: service, path: channel.thumb, serverID: model.serverID,
                                    width: 320, height: 180, contentMode: .fit)
                                Text([channel.displayNumber, channel.displayTitle].compactMap { $0 }.joined(separator: " · "))
                                    .font(.headline).lineLimit(2)
                                    .frame(width: 320, alignment: .leading)
                            }.frame(width: 320, alignment: .leading)
                        }.buttonStyle(.card)
                    }
                }
            }.modifier(TVDeckPageInsets())
        }
        .background { TVDeckBackground().ignoresSafeArea() }
        .navigationTitle("")
        .searchable(text: $query, prompt: "Channels")
        .task(id: service.liveTVServerID) { await model.load() }
        .fullScreenCover(item: $presentation, onDismiss: {
            let retired = lastPlayback
            lastPlayback = nil
            Task { await retired?.finish() }
        }) { session in
            session
        }
    }
}

/// The cover's item owns every input needed to render it. Never read a second
/// optional @State value from the cover closure: its first snapshot can be nil
/// even though SwiftUI has already activated the modal and blocked grid focus.
struct TVLivePlayerPresentation: Identifiable, View {
    let id = UUID()
    let provider: PlexLiveTVProvider
    let channel: PlexLiveChannel
    let serverID: String?
    let playback: TVLivePlayback

    var body: some View {
        TVLivePlayerScreen(provider: provider, channel: channel,
            serverID: serverID, playback: playback)
    }
}
