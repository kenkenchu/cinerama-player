import SwiftUI

struct LiveTVView: View {
    let viewModel: LiveTVViewModel
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            LiveTVRootContent(viewModel: viewModel)
                .cineramaAppNavigationDestinations()
        }
    }
}

struct LiveTVRootContent: View {
    @Environment(PlaybackCoordinator.self) private var playback
    let viewModel: LiveTVViewModel
    @State private var searchText = ""

    private var filteredChannels: [PlexLiveChannel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.channels }
        return viewModel.channels.filter { channel in
            [channel.displayTitle, channel.displayNumber, channel.callSign]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            if viewModel.isLoading, viewModel.lineup == nil {
                FeatureLoadingView()
            } else if let error = viewModel.error, viewModel.lineup == nil {
                FeatureErrorView(message: error) { Task { await viewModel.load(force: true) } }
            } else if !viewModel.isAvailable {
                FeatureEmptyStateView(
                    systemImage: "dot.radiowaves.left.and.right", title: "Live TV isn’t available",
                    message: "Set up a tuner and channels on your Plex server."
                )
            } else if viewModel.channels.isEmpty {
                FeatureEmptyStateView(
                    systemImage: "tv", title: "No channels available",
                    message: "Check the channel lineup on your Plex server, then refresh."
                )
            } else if filteredChannels.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                channelGrid
            }
        }
        .navigationTitle("Live TV")
        .searchable(text: $searchText, prompt: "Search channels by name or number")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh Channels", systemImage: "arrow.clockwise") {
                    Task { await viewModel.load(force: true) }
                }
                .disabled(viewModel.isLoading)
                .help("Refresh channels")
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load(force: true) }
    }

    private var channelGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(filteredChannels.count) \(filteredChannels.count == 1 ? "channel" : "channels")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if viewModel.isLoading { ProgressView().controlSize(.small) }
                }
                if let error = viewModel.error {
                    HStack {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                        Button("Retry") { Task { await viewModel.load(force: true) } }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)], spacing: 16) {
                    ForEach(filteredChannels) { channel in
                        LiveTVChannelCard(
                            channel: channel,
                            logoURL: viewModel.imageURL(for: channel.thumb, width: 400, height: 200),
                            isPlaying: playback.activePlaybackServerID == viewModel.serverID &&
                                playback.activeLiveTVContext?.channel.id == channel.id
                        ) {
                            guard let lineup = viewModel.lineup else { return }
                            Task { await playback.playLiveTV(channel: channel, program: nil, lineup: lineup) }
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }
}

/// A channel is playable without schedule metadata. Reused by Home and Live TV.
struct LiveTVChannelCard: View {
    let channel: PlexLiveChannel
    let logoURL: URL?
    var isPlaying = false
    let play: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let logoURL {
                        CineramaAsyncImage(url: logoURL) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFit().padding(20)
                            } else { placeholder }
                        }
                    } else { placeholder }
                }
                .frame(height: 100)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .padding(10)
                        .opacity(isPlaying || isHovered ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    HStack {
                        if let number = channel.displayNumber { Text(number) }
                        Spacer(minLength: 4)
                        if isPlaying { Text("Playing").fontWeight(.medium) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 14)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.primary.opacity(isPlaying ? 0.55 : isHovered ? 0.25 : 0.08), lineWidth: isPlaying ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("Watch \(channel.displayTitle)")
        .accessibilityLabel("Watch \(channel.displayTitle)\(channel.displayNumber.map { ", channel \($0)" } ?? "")")
        .accessibilityValue(isPlaying ? "Playing" : "")
    }

    private var placeholder: some View {
        Image(systemName: "tv")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
    }
}
