import SwiftUI

/// The Mac Home composition, presented with native remote-focus controls.
/// Never rotate a title while one of its actions has remote focus.
struct TVHomeHero: View {
    let service: PlexService
    let home: HomeViewModel
    let items: [PlexItem]
    let isActive: Bool
    let selectionReset: Int
    let isPreparing: Bool
    let play: (PlexItem) -> Void
    let details: (PlexItem) -> Void
    let navigate: (PlexItemID) -> Void
    @State private var selectedID: PlexItemID?
    @State private var isVisible = false
    @State private var backdropWidth = 1920
    @State private var logo = TVArtworkModel()
    @FocusState private var focusedAction: Action?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private enum Action: Hashable { case play, details, previous, next }
    private var index: Int { items.firstIndex { $0.id == selectedID } ?? 0 }
    private var item: PlexItem? { items.indices.contains(index) ? items[index] : nil }
    private var rotationKey: String {
        "\(item?.id.storageKey ?? "-")|\(isActive)|\(isVisible)|\(focusedAction != nil)|\(scenePhase)|\(reduceMotion)|\(selectionReset)|\(isPreparing)"
    }

    var body: some View {
        GeometryReader { geometry in
            if let item {
                ZStack(alignment: .bottomLeading) {
                    TVArtwork(service: service, path: backgroundPath(item), serverID: item.serverID,
                        width: geometry.size.width, height: geometry.size.height, cornerRadius: 0, showsPlaceholder: false)
                        .overlay {
                            LinearGradient(colors: [.black.opacity(0.92), .black.opacity(0.35), .clear],
                                startPoint: .leading, endPoint: .trailing)
                        }
                        .overlay {
                            LinearGradient(colors: [.clear, .black.opacity(0.25), .black],
                                startPoint: .center, endPoint: .bottom)
                        }
                        .id(item.id)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("CONTINUE WATCHING")
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .tracking(3).foregroundStyle(.white.opacity(0.65))
                        Group {
                            if let image = logo.image {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(maxWidth: 520, maxHeight: 100, alignment: .leading)
                                    .accessibilityLabel(home.displayTitle(for: item))
                            } else {
                                Text(home.displayTitle(for: item)).font(.largeTitle.bold())
                                    .lineLimit(2).minimumScaleFactor(0.75)
                            }
                        }.frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100, alignment: .bottomLeading)
                        if let episode = home.heroEpisodeTitle(for: item) {
                            Text(episode).font(.title3.weight(.semibold)).lineLimit(1)
                        }
                        Text(home.heroMetadata(for: item).joined(separator: " · "))
                            .font(.callout).foregroundStyle(.white.opacity(0.8))
                        if let summary = home.heroSummary(for: item) {
                            Text(summary).font(.body).lineLimit(2).foregroundStyle(.white.opacity(0.85))
                        }
                        HStack(spacing: 28) {
                            Button { play(item) } label: {
                                HStack {
                                    if isPreparing { ProgressView() }
                                    else { Image(systemName: "play.fill") }
                                    Text(home.heroPrimaryActionTitle(for: item))
                                }.frame(minWidth: 240)
                            }
                            .modifier(TVDeckActionStyle(prominent: true))
                            .focused($focusedAction, equals: .play)
                            .overlay {
                                if let progress = home.progress(for: item) {
                                    GeometryReader { geometry in
                                        Rectangle().fill(.black.opacity(0.16))
                                            .frame(width: geometry.size.width * min(1, max(0, progress)))
                                    }.clipShape(.capsule).allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                            .disabled(isPreparing)
                            .accessibilityValue(home.progress(for: item).map { "\(Int(min(1, max(0, $0)) * 100)) percent watched" } ?? "")
                            .contextMenu {
                                TVHomeItemActions(item: item, home: home, navigate: navigate, canRemove: true)
                            }
                            Button("Details", systemImage: "info.circle") { details(item) }
                                .modifier(TVDeckActionStyle())
                                .focused($focusedAction, equals: .details)
                        }.padding(.top, 8)
                    }
                    .frame(width: min(680, geometry.size.width * 0.48), alignment: .leading)
                    .padding(28)
                    .modifier(TVDeckInformationPanel())
                    .environment(\.colorScheme, .dark)
                    .padding(36)
                }
                .clipShape(.rect(cornerRadius: 28))
                .overlay { TVViewportEdge() }
                .overlay(alignment: .topTrailing) {
                    if items.count > 1 { pager.padding(32) }
                }
                .onAppear { backdropWidth = Int(geometry.size.width) }
                .foregroundStyle(.white)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: item.id)
            }
        }
        .frame(height: TVDeckLayout.heroHeight)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: selectionReset) { _, _ in selectedID = items.first?.id }
        .onChange(of: items.map(\.id)) { _, ids in
            if selectedID.map({ !ids.contains($0) }) ?? true { selectedID = ids.first }
        }
        .task(id: rotationKey) {
            guard isActive, isVisible, focusedAction == nil, scenePhase == .active,
                  !reduceMotion, !isPreparing, items.count > 1 else { return }
            do { try await Task.sleep(for: .seconds(7)) } catch { return }
            guard !Task.isCancelled else { return }
            advance(1)
        }
        .task(id: item?.id) {
            guard let item else { return }
            await logo.load(service: service, path: item.clearLogo, serverID: item.serverID, width: 520, height: 130)
            guard !Task.isCancelled, items.count > 1 else { return }
            let next = items[(index + 1) % items.count]
            // One next backdrop only: keep the A8 cache and decoding work bounded.
            let prefetch = TVArtworkModel()
            await prefetch.load(service: service, path: backgroundPath(next), serverID: next.serverID,
                width: backdropWidth, height: Int(TVDeckLayout.heroHeight))
        }
    }

    private var pager: some View {
        HStack(spacing: 16) {
            Button { advance(-1) } label: { Image(systemName: "chevron.left") }
                .modifier(TVDeckActionStyle())
                .focused($focusedAction, equals: .previous).accessibilityLabel("Previous title")
            Text("\(index + 1) / \(items.count)").font(.caption2.monospacedDigit())
            Button { advance(1) } label: { Image(systemName: "chevron.right") }
                .modifier(TVDeckActionStyle())
                .focused($focusedAction, equals: .next).accessibilityLabel("Next title")
        }
        .padding(12)
        .background(.black.opacity(0.7), in: .capsule)
    }

    private func advance(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedID = items[(index + delta + items.count) % items.count].id
    }

    private func backgroundPath(_ item: PlexItem) -> String? {
        item.type == .episode
            ? item.grandparentArt ?? item.art ?? item.banner ?? item.thumb ?? item.grandparentThumb
            : item.preferredLandscapePath
    }
}
