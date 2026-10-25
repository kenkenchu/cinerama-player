import Foundation

@MainActor
@Observable
final class LiveTVViewModel {
    private let plexService: PlexService

    private(set) var provider: PlexLiveTVProvider?
    private(set) var channels: [PlexLiveChannel] = []
    private(set) var lineup: PlexLiveTVLineup?
    private(set) var serverID: String?
    private(set) var isLoading = false
    private(set) var isAvailable = false
    private(set) var error: String?

    private var discoveryCompleted = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(plexService: PlexService) {
        self.plexService = plexService
    }

    private func resetIfServerChanged() {
        guard serverID != plexService.liveTVServerID else { return }
        provider = nil
        channels = []
        lineup = nil
        discoveryCompleted = false
        serverID = plexService.liveTVServerID
    }

    func discover() async {
        resetIfServerChanged()
        guard !discoveryCompleted else { return }
        do {
            provider = try await plexService.getLiveTVProvider(serverID: serverID)
            isAvailable = provider != nil
            discoveryCompleted = true
        } catch {
            // Optional discovery never blocks Home; opening Live TV retries.
            isAvailable = false
        }
    }

    /// Home and the tab share one request. Navigating between them while loading
    /// must await that request rather than leave the destination without data.
    func load(force: Bool = false) async {
        if let loadTask {
            await loadTask.value
            return
        }
        resetIfServerChanged()
        guard force || lineup == nil else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadChannels(force: force)
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func loadChannels(force: Bool) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let targetID = serverID
        do {
            let resolvedProvider: PlexLiveTVProvider?
            if provider == nil || force {
                resolvedProvider = try await plexService.getLiveTVProvider(serverID: targetID)
            } else {
                resolvedProvider = provider
            }
            guard targetID == plexService.liveTVServerID else { return }
            provider = resolvedProvider
            guard let provider = resolvedProvider else {
                isAvailable = false
                discoveryCompleted = true
                channels = []
                lineup = nil
                return
            }
            let loadedChannels = try await plexService.getLiveTVChannels(provider: provider, serverID: targetID)
            guard targetID == plexService.liveTVServerID else { return }
            channels = loadedChannels
            // Playback needs the provider/channel snapshot, never an EPG.
            lineup = PlexLiveTVLineup(
                provider: provider,
                guides: channels.map { PlexLiveChannelGuide(channel: $0, programs: []) }
            )
            isAvailable = true
            discoveryCompleted = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func imageURL(for path: String?, width: Int, height: Int) -> URL? {
        plexService.imageURL(for: path, serverID: serverID, width: width, height: height)
    }
}
