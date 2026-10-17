import SwiftUI

struct SeerrMediaDetailView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: SeerrMediaDetailViewModel

    private let horizontalPadding = DuskPosterMetrics.detailHorizontalPadding

    init(mediaType: SeerrMediaType, mediaID: Int, service: SeerrService) {
        _viewModel = State(initialValue: SeerrMediaDetailViewModel(
            mediaType: mediaType,
            mediaID: mediaID,
            service: service
        ))
    }

    var body: some View {
        ZStack {
            Color.duskBackground.ignoresSafeArea()

            if viewModel.isLoading && viewModel.details == nil {
                FeatureLoadingView()
            } else if let error = viewModel.error, viewModel.details == nil {
                FeatureErrorView(message: error) {
                    Task { await viewModel.load() }
                }
            } else if viewModel.details != nil {
                content
            }
        }

        .toolbarColorScheme(.dark, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .task { await viewModel.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, viewModel.details != nil else { return }
            Task { try? await viewModel.refresh() }
        }
        .alert(
            "Couldn’t Send Request",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    private var content: some View {
        GeometryReader { geometry in
            let backgroundWidth: CGFloat = {
                geometry.size.width
            }()
            let leadingInset: CGFloat = {
                0
            }()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(
                        topInset: geometry.safeAreaInsets.top,
                        containerWidth: backgroundWidth,
                        containerHeight: geometry.size.height,
                        leadingInset: leadingInset
                    )

                    if detailShowsSynopsisBelowHero(for: sizeClass),
                       let overview = viewModel.overview?.nilIfEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Synopsis")
                                .font(DuskFont.sectionHeader(style: .title3.bold()))
                            Text(overview)

                                .foregroundStyle(Color.duskTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.top, 28)
                    }

                    if viewModel.mediaType == .tv, !viewModel.seasons.isEmpty {
                        MediaCarousel(title: "Seasons") {
                            ForEach(viewModel.seasons) { season in
                                PosterNavigationCard(
                                    route: .seerrSeason(
                                        tvID: viewModel.mediaID,
                                        seasonNumber: season.seasonNumber
                                    ),
                                    imageURL: viewModel.posterURL(
                                        for: season,
                                        width: Int(DuskPosterMetrics.carouselPosterWidth * 2)
                                    ),
                                    title: season.name,
                                    subtitle: season.episodeCount.map {
                                        $0 == 1 ? "1 episode" : "\($0) episodes"
                                    },
                                    width: DuskPosterMetrics.carouselPosterWidth,
                                    availabilityBadge: viewModel.seasonState(season.seasonNumber).badgeTitle
                                )
                            }
                        }
                        .padding(.top, 40)
                        .padding(.bottom, 56)
                    } else {
                        Spacer(minLength: 56)
                    }
                }
                .padding(.top, -geometry.safeAreaInsets.top)
                .frame(width: geometry.size.width, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                try? await viewModel.refresh()
            }

        }
    }

    private func hero(
        topInset: CGFloat,
        containerWidth: CGFloat,
        containerHeight: CGFloat,
        leadingInset: CGFloat
    ) -> some View {
        let heroBase = min(max(containerHeight * 0.72, 520), 760)
        return DetailHeroSection(
            backdropURL: viewModel.backdropURL(width: Int(containerWidth.rounded(.up))),
            title: viewModel.title,
            descriptionText: viewModel.overview,
            topInset: topInset,
            containerWidth: containerWidth,
            backgroundLeadingInset: leadingInset,
            heroBaseHeight: heroBase
        ) {
            VStack(alignment: detailHeroContentAlignment(for: sizeClass), spacing: 6) {
                let metadata = [
                    viewModel.year.map(String.init),
                    viewModel.runtimeText,
                    viewModel.mediaType == .tv ? "TV Show" : "Movie",
                ].compactMap { $0 }
                Text(metadata.joined(separator: " · "))
                    .font(DuskFont.metadata(style: .subheadline.weight(.medium)))
                    .foregroundStyle(Color.primary.opacity(0.78))

                if let genres = viewModel.genreText {
                    Text(genres)
                        .font(DuskFont.caption(style: .caption))
                        .foregroundStyle(Color.primary.opacity(0.72))
                }

                if let rating = viewModel.rating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(DuskFont.caption(style: .caption))
                        .foregroundStyle(Color.primary.opacity(0.78))
                }
            }
        } actions: {
            if viewModel.canRequest {
                Button {
                    viewModel.showsRequestConfirmation = true
                } label: {
                    DetailHeroPrimaryActionButtonLabel(
                        title: viewModel.requestButtonTitle,
                        systemImage: "paperplane.fill",
                        fillsWidth: usesFullWidthDetailActionButtons(for: sizeClass)
                    )
                }
                .detailHeroNativePrimaryButtonStyle()
                .disabled(viewModel.isRequesting)
                .confirmationDialog(
                    viewModel.mediaType == .movie
                        ? "Request this movie?"
                        : "Request missing seasons?",
                    isPresented: $viewModel.showsRequestConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Request") {
                        Task { await viewModel.request() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The request will be sent to Seerr as \(viewModel.title).")
                }
            } else {
                DetailHeroStatusActionLabel(
                    title: viewModel.requestButtonTitle,
                    systemImage: viewModel.requestState.systemImage,
                    fillsWidth: usesFullWidthDetailActionButtons(for: sizeClass)
                )
            }
        }
    }
}
