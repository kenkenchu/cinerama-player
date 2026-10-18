import Foundation

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
