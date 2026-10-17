import SwiftUI

struct SubtitleSearchView: View {
    @State private var viewModel: SubtitleSearchViewModel
    private let onDismiss: () -> Void


    init(
        plexService: PlexService,
        ratingKey: String,
        serverID: String?,
        preferredLanguageCode: String?,
        onDownloaded: @escaping (PlexSubtitleSearchResult) async -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: SubtitleSearchViewModel(
            plexService: plexService,
            ratingKey: ratingKey,
            serverID: serverID,
            preferredLanguageCode: preferredLanguageCode,
            onDownloaded: onDownloaded
        ))
        self.onDismiss = onDismiss
    }

    /// For callers that build the view model themselves (detail screens route
    /// through their own view model so the view stays off `PlexService`).
    init(viewModel: SubtitleSearchViewModel, onDismiss: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onDismiss = onDismiss
    }

    var body: some View {
        searchContent
    }

    // MARK: - Search

    private var searchContent: some View {
        @Bindable var vm = viewModel

        return NavigationStack {
            List {
                Section {
                    Picker("Language", selection: $vm.language) {
                        ForEach(CommonLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Hearing Impaired", isOn: $vm.hearingImpaired)

                    Button {
                        Task { await viewModel.search() }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .disabled(viewModel.isBusy)
                } footer: {
                    Text(Self.providerFootnote)
                }
                .listRowBackground(Color.duskSurface)

                if let errorMessage = viewModel.errorMessage, !viewModel.results.isEmpty {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.duskTextSecondary)
                    }
                    .listRowBackground(Color.duskSurface)
                }

                Section {
                    resultsSection
                }
                .listRowBackground(Color.duskSurface)
            }
            .scrollContentBackground(.hidden)
            .background(Color.duskBackground)
            .navigationTitle("Download Subtitles")

            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.duskBackground)
        .task { await searchOnFirstAppearance() }
        .onChange(of: viewModel.language) { _, _ in reloadForChangedQuery() }
        .onChange(of: viewModel.hearingImpaired) { _, _ in reloadForChangedQuery() }
        .onChange(of: viewModel.didDownload) { _, didDownload in
            guard didDownload else { return }
            dismissAfterSuccess()
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch viewModel.phase {
        case .searching:
            HStack(spacing: 12) {
                FeatureLoadingView()
                Text("Searching…")
                    .foregroundStyle(Color.duskTextSecondary)
            }

        case .empty:
            centeredStateRow {
                FeatureEmptyStateView(
                    systemImage: "captions.bubble",
                    title: "No Subtitles Found",
                    message: "Try another language or turn off the Hearing Impaired filter."
                )
            }

        case .downloaded:
            centeredStateRow {
                FeatureEmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "Subtitle Added",
                    message: "Plex installed it next to the media file."
                )
            }

        case let .error(message) where viewModel.results.isEmpty:
            centeredStateRow {
                FeatureErrorView(message: message) {
                    Task { await viewModel.search() }
                }
            }

        default:
            if viewModel.results.isEmpty {
                centeredStateRow {
                    FeatureEmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "Search for Subtitles",
                        message: nil
                    )
                }
            } else {
                ForEach(viewModel.results) { result in
                    Button {
                        Task { await viewModel.download(result) }
                    } label: {
                        resultRow(result)
                    }
                    .disabled(viewModel.isBusy)
                }
            }
        }
    }

    private func centeredStateRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: - Search Results


    // MARK: - Shared row

    private func resultRow(_ result: PlexSubtitleSearchResult) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.displayTitle)
                        .foregroundStyle(Color.duskTextPrimary)
                        .lineLimit(2)

                    if result.isHearingImpaired == true {
                        badge("HI")
                    }
                    if result.isForced == true {
                        badge("Forced")
                    }
                }

                if !result.detailText.isEmpty {
                    Text(result.detailText)
                        .font(DuskFont.caption(style: .caption))
                        .foregroundStyle(Color.duskTextSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            if viewModel.downloadingResultID == result.id {
                FeatureLoadingView()
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(DuskFont.glyphMedium(style: .body.weight(.semibold)))
                    .foregroundStyle(Color.duskTextSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(DuskFont.badge(style: .caption2.weight(.bold)))
            .foregroundStyle(Color.duskTextSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.duskTextSecondary.opacity(0.16), in: Capsule())
    }

    // MARK: - Shared behavior

    private static let providerFootnote =
        "Plex searches OpenSubtitles and saves the file next to the media."

    private func searchOnFirstAppearance() async {
        guard viewModel.results.isEmpty, viewModel.phase == .idle else { return }
        await viewModel.search()
    }

    private func reloadForChangedQuery() {
        viewModel.queryDidChange()
        Task { await viewModel.search() }
    }

    private func dismissAfterSuccess() {
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            onDismiss()
        }
    }
}
