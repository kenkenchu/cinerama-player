import SwiftUI

struct ServerPrioritySettingsView: View {
    @Environment(PlexService.self) private var plexService
    @Environment(ServerConnectionCoordinator.self) private var connections
    @State private var viewModel: ServerPrioritySettingsViewModel?

    var body: some View {
        content
            .background(Color.duskBackground.ignoresSafeArea())
            .navigationTitle("Server Priority")

            .task {
                let model = viewModel ?? ServerPrioritySettingsViewModel(
                    plexService: plexService,
                    connections: connections
                )
                viewModel = model
                await model.load()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            if viewModel.rows.isEmpty {
                if viewModel.isLoading {
                    FeatureLoadingView()
                } else {
                    FeatureErrorView(
                        message: viewModel.accountError ?? Self.noServersMessage,
                        retryTitle: "Check Again"
                    ) {
                        Task { await viewModel.refresh() }
                    }
                }
            } else {
                editor(viewModel)
            }
        } else {
            FeatureLoadingView()
        }
    }

    @ViewBuilder
    private func editor(_ viewModel: ServerPrioritySettingsViewModel) -> some View {
        listEditor(viewModel)
    }


    private func listEditor(_ viewModel: ServerPrioritySettingsViewModel) -> some View {
        List {
            if !viewModel.hasEnabledServer {
                Section {
                    ServerPriorityNotice(message: Self.nothingEnabledMessage)
                }
                .listRowBackground(Color.duskSurface)
            }

            Section {
                ForEach(viewModel.rows) { row in
                    ServerPriorityRow(row: row, viewModel: viewModel)
                }
                .onMove { offsets, destination in
                    viewModel.move(fromOffsets: offsets, toOffset: destination)
                }
            } header: {
                Text(viewModel.isSingleServer ? "Server" : "Priority")
                    .foregroundStyle(Color.duskTextSecondary)
            } footer: {
                Text(Self.footerText(isSingleServer: viewModel.isSingleServer))
                    .foregroundStyle(Color.duskTextSecondary)
            }
            .listRowBackground(Color.duskSurface)

            Section {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    HStack {
                        Text("Check Again")
                            .foregroundStyle(Color.duskTextPrimary)

                        Spacer()

                        if viewModel.isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isRefreshing)

            } footer: {
                if let accountError = viewModel.accountError {
                    Text(accountError)
                        .foregroundStyle(Color.duskTextSecondary)
                } else {
                    Text(Self.refreshFooterText)
                        .foregroundStyle(Color.duskTextSecondary)
                }
            }
            .listRowBackground(Color.duskSurface)
        }
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .toolbar {
            if !viewModel.isSingleServer {
            }
        }
    }

    // MARK: - Copy

    private static let noServersMessage = "No Plex servers found on your account."
    private static let nothingEnabledMessage = "Every server is turned off, so Dusk has nothing to show. Downloads still play. Turn a server back on to bring your libraries back."
    private static let refreshFooterText = "Looks for servers that have come online or been shared with you since Dusk last checked."

    private static func footerText(isSingleServer: Bool) -> String {
        guard !isSingleServer else {
            return "Dusk uses this server for everything. Turning it off leaves Dusk with nothing to show until you turn it back on."
        }
        return "Dusk uses every server that is on and merges what they hold. When the same title is on more than one, the server highest in this list plays it. A server that is off is ignored completely — no libraries, no Continue Watching, no search results."
    }
}

// MARK: - Shared pieces

/// The server glyph, matching the icon containers used by the
/// other settings rows.
private struct ServerPriorityIcon: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    let iconFont: Font

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.duskTextSecondary.opacity(0.14))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "server.rack")
                    .font(iconFont)
                    .foregroundStyle(Color.duskTextPrimary)
            }
    }
}

private struct ServerPriorityNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.duskTextSecondary)

            Text(message)
                .foregroundStyle(Color.duskTextSecondary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.vertical, 4)
    }
}


private struct ServerPriorityRow: View {
    let row: ServerPrioritySettingsViewModel.Row
    let viewModel: ServerPrioritySettingsViewModel

    var body: some View {
        HStack(spacing: 14) {
            ServerPriorityIcon(size: 36, cornerRadius: 12, iconFont: .subheadline.weight(.semibold))
                .opacity(row.isEnabled ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(row.isEnabled ? Color.duskTextPrimary : Color.duskTextSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(row.ownership)
                        .foregroundStyle(Color.duskTextSecondary)
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(Color.duskTextSecondary)

                    ConnectionStatusDot(tone: row.tone, size: 7)

                    Text(row.status)
                        .foregroundStyle(Color.duskTextSecondary)
                }
                .font(.caption)
            }

            Spacer(minLength: 12)

            Toggle(
                "Use \(row.name)",
                isOn: Binding(
                    get: { row.isEnabled },
                    set: { viewModel.setEnabled($0, for: row.id) }
                )
            )
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status dot

/// Shared with the Seerr status row. Deliberately not the coral accent: next to
/// a status word, coral reads as an error.
struct ConnectionStatusDot: View {
    let tone: ConnectionStatusTone
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch tone {
        case .good: .green
        case .degraded: .yellow
        case .bad: .red
        case .neutral: Color.duskTextSecondary.opacity(0.5)
        }
    }
}
