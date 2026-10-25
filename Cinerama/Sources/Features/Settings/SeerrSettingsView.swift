import SwiftUI

struct SeerrSettingsView: View {
    @Environment(SeerrService.self) private var seerrService
    @State private var viewModel = SeerrSettingsViewModel()

    var body: some View {
        Group {
            settingsContent
        }
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle("Seerr")
        .task {
            viewModel.load(from: seerrService)
        }
        .confirmationDialog(
            "Connect to Seerr?",
            isPresented: $viewModel.showsConnectionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Connect") {
                Task { await viewModel.connect(using: seerrService) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.confirmationMessage)
        }
    }

    private var settingsContent: some View {
        List {
            Section {
                TextField("Server URL", text: $viewModel.serverURL)
                    .disabled(seerrService.isConnected || viewModel.isWorking)

                connectionRow
            } header: {
                Text("Server")
            } footer: {
                Text("Enter the address you use for Seerr.")
            }
            .listRowBackground(Color.cineramaSurface)

            if let errorMessage = viewModel.errorMessage ?? seerrService.lastConnectionError {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.cineramaTextSecondary)
                }
                .listRowBackground(Color.cineramaSurface)
            }

            Section {
                if seerrService.isConnected {
                    Button("Disconnect", role: .destructive) {
                        Task { await viewModel.disconnect(using: seerrService) }
                    }
                    .disabled(viewModel.isWorking)
                } else {
                    Button {
                        Task { await viewModel.prepareConnection(using: seerrService) }
                    } label: {
                        HStack {
                            Text("Connect with Plex")
                            Spacer()
                            if viewModel.isWorking {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(viewModel.isWorking || viewModel.serverURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .listRowBackground(Color.cineramaSurface)
        }
        .scrollContentBackground(.hidden)
    }


    private var connectionRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")

                    .foregroundStyle(Color.cineramaTextPrimary)
                Text(seerrService.connectionSubtitle)
                    .font(CineramaFont.caption(style: .caption))
                    .foregroundStyle(Color.cineramaTextSecondary)
            }
            Spacer()
            ConnectionStatusDot(tone: seerrStatusTone)
        }
        .frame(minHeight: 52)
    }

    private var seerrStatusTone: ConnectionStatusTone {
        if seerrService.lastConnectionError != nil { return .bad }
        return seerrService.isConnected ? .good : .neutral
    }


}
