import SwiftUI

struct LibraryOrderSettingsView: View {
    @Environment(PlexService.self) private var plexService
    @State private var viewModel: LibraryOrderSettingsViewModel?

    var body: some View {
        content
            .background(Color.duskBackground.ignoresSafeArea())
            .navigationTitle("Library Order")

            .task {
                let model = viewModel ?? LibraryOrderSettingsViewModel(plexService: plexService)
                viewModel = model
                await model.load()
            }
            .onDisappear {
                guard let viewModel else { return }
                // The debounce may still be counting down; leaving the screen
                // must not drop the edit.
                Task { await viewModel.flushPendingWrite() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            if viewModel.isLoading, viewModel.libraries.isEmpty {
                FeatureLoadingView()
            } else if let error = viewModel.error, viewModel.libraries.isEmpty {
                FeatureErrorView(message: error) {
                    Task { await viewModel.load() }
                }
            } else {
                editor(viewModel)
            }
        } else {
            FeatureLoadingView()
        }
    }

    @ViewBuilder
    private func editor(_ viewModel: LibraryOrderSettingsViewModel) -> some View {
        listEditor(viewModel)
    }


    private func listEditor(_ viewModel: LibraryOrderSettingsViewModel) -> some View {
        List {
            Section {
                ForEach(viewModel.libraries) { library in
                    Label(
                        viewModel.displayTitle(for: library),
                        systemImage: Self.iconName(for: library)
                    )
                    .foregroundStyle(Color.duskTextPrimary)
                }
                .onMove { offsets, destination in
                    viewModel.move(fromOffsets: offsets, toOffset: destination)
                }
            } header: {
                HStack {
                    Text("Order")
                        .foregroundStyle(Color.duskTextSecondary)

                    Spacer()

                    if viewModel.isSaving {
                        ProgressView()
                    }
                }
            } footer: {
                Text("Drag to set the order of your libraries. The order is saved to your Plex account, so other Plex apps use it too.")
                    .foregroundStyle(Color.duskTextSecondary)
            }
            .listRowBackground(Color.duskSurface)

            if let saveError = viewModel.saveError {
                Section {
                    Text(saveError)
                        .foregroundStyle(Color.duskTextSecondary)
                }
                .listRowBackground(Color.duskSurface)
            }
        }
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .toolbar {
        }
    }

    // MARK: - Shared

    /// Music and photo sections are listed here even though Dusk cannot browse
    /// them, so they need icons `PlexLibraryType` does not model.
    private static func iconName(for library: PlexLibrary) -> String {
        if let systemImage = library.libraryType?.systemImage {
            return systemImage
        }

        switch library.type {
        case "artist":
            return "music.note"
        case "photo":
            return "photo"
        default:
            return "folder"
        }
    }
}
