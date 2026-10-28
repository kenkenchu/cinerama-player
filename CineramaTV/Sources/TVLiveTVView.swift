import SwiftUI

struct TVLiveTVView: View {
    let service: PlexService
    @State private var model: LiveTVViewModel
    @State private var query = ""
    @State private var presentation: TVLivePlayerPresentation?
    @State private var lastPlayback: TVLivePlayback?
    @AppStorage("tvExperimentalLiveMPEG2Mode") private var mode = "disabled"

    init(service: PlexService) {
        self.service = service
        _model = State(initialValue: LiveTVViewModel(plexService: service))
    }

    private var enabled: Bool { mode == "cpu" || mode == "metal" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Live TV · Experimental").font(.largeTitle)
                Text("HD SDR MPEG-2 channels · Local decoding · No server video/audio conversion")
                    .foregroundStyle(.secondary)
                Picker("Live TV decoder", selection: $mode) {
                    Text("Disabled").tag("disabled")
                    Text("Experimental CPU").tag("cpu")
                    Text("Experimental Metal").tag("metal")
                }
                Text("Changes apply on the next tune. No captions, DVR, seeking or recording. Apple TV HD performance requires device verification.")
                    .font(.callout).foregroundStyle(.secondary)
                if enabled {
                    if model.isLoading { ProgressView("Loading channels…") }
                    if model.error != nil { Text("Could not load channels. Check your Plex server and retry.") }
                    Button("Refresh Channels") { Task { await model.load(force: true) } }
                    if !model.isLoading && model.channels.isEmpty && model.error == nil {
                        Text("No Live TV channels on the highest-priority connected server.")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 40)], spacing: 40) {
                        ForEach(model.channels.filter {
                            query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query)
                                || ($0.displayNumber ?? "").localizedCaseInsensitiveContains(query)
                        }) { channel in
                            Button {
                                guard let provider = model.provider else { return }
                                let playback = TVLivePlayback(service: service, mode: mode == "metal" ? .metal : .cpu)
                                lastPlayback = playback
                                presentation = TVLivePlayerPresentation(provider: provider, channel: channel,
                                    serverID: model.serverID, playback: playback)
                            } label: {
                                VStack(spacing: 12) {
                                    TVArtwork(service: service, path: channel.thumb, serverID: model.serverID,
                                        width: 280, height: 140)
                                    Text([channel.displayNumber, channel.displayTitle].compactMap { $0 }.joined(separator: " · "))
                                        .lineLimit(2)
                                }.padding(15)
                            }.buttonStyle(.card)
                        }
                    }
                }
            }.padding(60)
        }
        .background { TVDeckBackground().ignoresSafeArea() }
        .navigationTitle("Live TV")
        .searchable(text: $query, prompt: "Channels")
        .task(id: "\(mode)|\(service.liveTVServerID ?? "")") { if enabled { await model.load() } }
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
