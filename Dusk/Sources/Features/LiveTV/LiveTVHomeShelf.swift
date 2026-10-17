import SwiftUI

struct LiveTVHomeShelf: View {
    @Environment(PlaybackCoordinator.self) private var playback
    let viewModel: LiveTVViewModel
    let play: (PlexLiveChannel, PlexLiveProgram?, PlexLiveTVLineup) -> Void

    var body: some View {
        if let lineup = viewModel.lineup, !lineup.channels.isEmpty {
            VStack(alignment: .leading, spacing: DuskPosterMetrics.carouselSectionSpacing) {
                Text("Live TV")
                    .font(DuskFont.sectionHeader(style: .title2.bold()))
                    .foregroundStyle(Color.duskTextPrimary)
                    .padding(.horizontal, DuskPosterMetrics.carouselHorizontalPadding)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 16) {
                        ForEach(lineup.channels) { channel in
                            LiveTVChannelCard(
                                channel: channel,
                                logoURL: viewModel.imageURL(for: channel.thumb, width: 400, height: 200),
                                isPlaying: playback.activePlaybackServerID == viewModel.serverID &&
                                    playback.activeLiveTVContext?.channel.id == channel.id
                            ) {
                                play(channel, nil, lineup)
                            }
                            .frame(width: 220)
                        }
                    }
                    .padding(.horizontal, DuskPosterMetrics.carouselHorizontalPadding)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
