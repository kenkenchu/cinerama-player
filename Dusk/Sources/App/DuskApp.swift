import AppIntents
import AVFoundation
import SwiftUI

enum AppImageCache {
    static let memoryCapacity = 0
    static let diskCapacity = 200_000_000
    static let maxAge: TimeInterval = 3 * 24 * 60 * 60

    private static let cachedAtUserInfoKey = "DuskCachedAt"

    static let shared = URLCache(
        memoryCapacity: memoryCapacity,
        diskCapacity: diskCapacity
    )

    static func configureSharedCache() {
        if URLCache.shared !== shared {
            URLCache.shared = shared
        }
    }

    static func clear() {
        shared.removeAllCachedResponses()
    }

    static func cachedResponse(for request: URLRequest, now: Date = .now) -> CachedURLResponse? {
        guard let response = shared.cachedResponse(for: request) else { return nil }

        guard isFresh(response, now: now) else {
            shared.removeCachedResponse(for: request)
            return nil
        }

        return response
    }

    static func storeCachedResponse(_ response: CachedURLResponse, for request: URLRequest, now: Date = .now) {
        var userInfo = response.userInfo ?? [:]
        userInfo[cachedAtUserInfoKey] = now

        let timestampedResponse = CachedURLResponse(
            response: response.response,
            data: response.data,
            userInfo: userInfo,
            storagePolicy: response.storagePolicy
        )
        shared.storeCachedResponse(timestampedResponse, for: request)
    }

    static func cachedAt(for response: CachedURLResponse) -> Date? {
        response.userInfo?[cachedAtUserInfoKey] as? Date
    }

    private static func isFresh(_ response: CachedURLResponse, now: Date) -> Bool {
        guard let cachedAt = cachedAt(for: response) else {
            return false
        }

        return now.timeIntervalSince(cachedAt) <= maxAge
    }
}


@main
struct DuskApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var plexService: PlexService
    @State private var seerrService: SeerrService
    @State private var playbackCoordinator: PlaybackCoordinator
    @State private var downloadManager: DownloadManager
    @State private var offlinePlaybackSyncManager: OfflinePlaybackSyncManager
    @State private var userPreferences: UserPreferences
    @State private var analytics: AnalyticsClient

    init() {
        AppImageCache.configureSharedCache()
        let service = PlexService()
        let seerr = SeerrService(plexService: service)
        let prefs = UserPreferences()
        let analyticsClient = AnalyticsClient(preferences: prefs)
        let downloads = DownloadManager(plexService: service, preferences: prefs)
        let playbackSync = OfflinePlaybackSyncManager(plexService: service)
        _plexService = State(initialValue: service)
        _seerrService = State(initialValue: seerr)
        _downloadManager = State(initialValue: downloads)
        _offlinePlaybackSyncManager = State(initialValue: playbackSync)
        _analytics = State(initialValue: analyticsClient)
        let coordinator = PlaybackCoordinator(
            plexService: service,
            preferences: prefs,
            downloadManager: downloads,
            offlinePlaybackSyncManager: playbackSync
        )
        _playbackCoordinator = State(initialValue: coordinator)
        // Siri's intents run in this process and reach the app through it.
        let siri = SiriPlaybackService(plexService: service, playback: coordinator)
        AppDependencyManager.shared.add(dependency: siri)
        _userPreferences = State(initialValue: prefs)
        Self.configurePlaybackAudioSession()
    }

    var body: some Scene {
        Window("Dusk", id: "main") { appContent }
            .defaultSize(width: 1200, height: 800)
            .commands { DuskMacCommands() }
    }

    private var appContent: some View {
        ContentView()
            .environment(plexService)
            .environment(seerrService)
            .environment(playbackCoordinator)
            .environment(downloadManager)
            .environment(offlinePlaybackSyncManager)
            .environment(userPreferences)
            .environment(analytics)
            .preferredColorScheme(userPreferences.appearanceMode.preferredColorScheme)
            .task {
                analytics.recordAppOpenedIfNeeded()
            }
            .task {
                PlaybackEngineFactory.prewarmIfNeeded()
            }
            .task(
                id: seerrContextID
            ) {
                await seerrService.contextDidChange()
            }
            .task(
                id: offlineContextID
            ) {
                guard plexService.homeBootstrapCompleted else {
                    offlinePlaybackSyncManager.stopAutomaticSync()
                    return
                }

                downloadManager.activateProfile()
                offlinePlaybackSyncManager.activateProfile()

                guard plexService.isSessionReady else {
                    offlinePlaybackSyncManager.stopAutomaticSync()
                    return
                }

                offlinePlaybackSyncManager.startAutomaticSync()
                await offlinePlaybackSyncManager.syncPendingActions(force: true)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    analytics.recordAppOpenedIfNeeded()
                }

                if newPhase == .active,
                   plexService.isSessionReady {
                    offlinePlaybackSyncManager.startAutomaticSync()
                    Task {
                        await offlinePlaybackSyncManager.syncPendingActions(force: true)
                    }
                } else {
                    offlinePlaybackSyncManager.stopAutomaticSync()
                }
            }
            .onChange(of: userPreferences.downloadsWifiOnly) {
                downloadManager.evaluateNetworkConstraints()
            }
            .onChange(of: userPreferences.analyticsEnabled) {
                analytics.reportingPreferenceDidChange()
            }
    }
}

private extension DuskApp {
    /// Seerr is bound to the account's first enabled server (see
    /// `SeerrService`), not to whichever server happens to be connected, so its
    /// context only changes when that binding or the profile does.
    var seerrContextID: String {
        [
            plexService.activeProfileID ?? "none",
            plexService.seerrBindingServerID ?? "none",
            String(plexService.isAuthenticated),
        ].joined(separator: ":")
    }

    /// Offline sync spans the whole pool: a second server coming up has to
    /// re-arm it, so the connected count is part of the identity.
    var offlineContextID: String {
        [
            String(plexService.homeBootstrapCompleted),
            plexService.activeProfileID ?? "none",
            plexService.pool.primary?.serverID ?? "none",
            String(plexService.pool.connections.count),
        ].joined(separator: ":")
    }

    static func configurePlaybackAudioSession() {
    }
}
