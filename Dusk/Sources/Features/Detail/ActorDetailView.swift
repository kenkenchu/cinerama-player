import SwiftUI

struct ActorDetailView: View {
    @State private var viewModel: ActorDetailViewModel

    private let horizontalPadding: CGFloat = DuskPosterMetrics.detailHorizontalPadding
    private let gridSpacing: CGFloat = {
        DuskPosterMetrics.detailGridSpacing
    }()
    private let preferredPosterWidth: CGFloat = {
        DuskPosterMetrics.detailGridPreferredWidth
    }()
    private let minimumColumnCount = 2

    init(person: PlexPersonReference, serverID: String? = nil, plexService: PlexService) {
        _viewModel = State(initialValue: ActorDetailViewModel(
            person: person,
            serverID: serverID,
            plexService: plexService
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.filmography.isEmpty {
                FeatureLoadingView()
            } else if let error = viewModel.error, viewModel.filmography.isEmpty {
                FeatureErrorView(message: error) {
                    Task { await viewModel.load() }
                }
            } else {
                contentView
            }
        }

        .toolbarColorScheme(.dark, for: DuskPlatform.navigationToolbarPlacement)
        .toolbarBackground(.hidden, for: DuskPlatform.navigationToolbarPlacement)
        .task {
            await viewModel.load()
        }
    }

    private var contentView: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 36)

                    if !viewModel.movies.isEmpty {
                        filmographySection(
                            title: "Movies",
                            items: viewModel.movies,
                            width: geometry.size.width
                        )
                    }

                    if !viewModel.shows.isEmpty {
                        filmographySection(
                            title: "Shows",
                            items: viewModel.shows,
                            width: geometry.size.width
                        )
                    }

                    if viewModel.movies.isEmpty && viewModel.shows.isEmpty && !viewModel.isLoading {
                        emptyState
                            .padding(.horizontal, horizontalPadding)
                    }
                }
                .padding(.bottom, 56)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        let artworkSize: CGFloat = {
            120
        }()
        let headerSpacing: CGFloat = {
            20
        }()

        return HStack(alignment: .center, spacing: headerSpacing) {
            personArtwork(size: artworkSize)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.person.name)
                    .font(DuskFont.pageTitle(style: .title2.bold()))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)

                if let roleName = viewModel.person.roleName, !roleName.isEmpty {
                    Text(roleName)
                        .font(DuskFont.metadata(style: .subheadline))
                        .foregroundStyle(Color.primary.opacity(0.78))
                }

                Text(viewModel.creditSummary)
                    .font(DuskFont.caption(style: .subheadline))
                    .foregroundStyle(Color.primary.opacity(0.76))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func personArtwork(size: CGFloat) -> some View {
        let imageSize = Int(size.rounded())
        let artworkShape = RoundedRectangle(cornerRadius: PosterArtwork.cornerRadius, style: .continuous)

        if let imageURL = viewModel.personImageURL(size: imageSize) {
            DuskAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    personPlaceholder(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(artworkShape)
        } else {
            personPlaceholder(size: size)
                .frame(width: size, height: size)
                .clipShape(artworkShape)
        }
    }

    private func personPlaceholder(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: PosterArtwork.cornerRadius, style: .continuous)
                .fill(Color.duskSurface)

            Image(systemName: "person.fill")
                .font(.system(size: size * 0.30, weight: .regular))
                .foregroundStyle(Color.duskTextSecondary)
        }
    }

    @ViewBuilder
    private func filmographySection(title: String, items: [PlexItem], width: CGFloat) -> some View {
        let layout = AdaptivePosterGridLayout.make(
            containerWidth: width,
            horizontalPadding: horizontalPadding,
            gridSpacing: gridSpacing,
            preferredPosterWidth: preferredPosterWidth,
            minimumColumnCount: minimumColumnCount
        )
        let sectionSpacing: CGFloat = {
            16
        }()

        VStack(alignment: .leading, spacing: sectionSpacing) {
            Text(title)
                .font(sectionTitleFont)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, horizontalPadding)

            PlexItemPosterGrid(
                items: items,
                layout: layout,
                posterURL: { item, width, height in
                    viewModel.posterURL(for: item, width: width, height: height)
                },
                subtitle: { viewModel.subtitle(for: $0) }
            )
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var sectionTitleFont: Font {
        DuskFont.sectionHeader(style: .headline)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No titles found")
                .font(DuskFont.rowTitle(style: .headline))
                .foregroundStyle(Color.primary)

            Text("This actor doesn't have any movies or shows available in your connected Plex library.")
                .font(DuskFont.caption(style: .subheadline))
                .foregroundStyle(Color.primary.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color.duskSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
