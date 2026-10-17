import SwiftUI
import AppKit
typealias DuskPlatformImage = NSImage

enum DuskAsyncImagePhase {
    case empty
    case success(Image)
    case failure(any Error)
}

struct DuskAsyncImage<Content: View>: View {
    @Environment(PlexService.self) private var plexService

    let url: URL?
    @ViewBuilder let content: (DuskAsyncImagePhase) -> Content

    @State private var phase = DuskAsyncImagePhase.empty

    var body: some View {
        content(phase)
            .task(id: url) {
                await loadImage()
            }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            phase = .empty
            return
        }

        phase = .empty

        do {
            let image = try await DuskImageLoader.shared.image(for: url, using: plexService)
            guard !Task.isCancelled else { return }
            phase = .success(Image(nsImage: image))
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }
}

actor DuskImageLoader {
    static let shared = DuskImageLoader()

    private let session: URLSession
    private let memoryCache = NSCache<NSURL, CachedMemoryImage>()
    private var inFlightTasks: [URL: Task<LoadedImage, Error>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = AppImageCache.shared
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30

        session = URLSession(configuration: configuration)
        memoryCache.countLimit = 512
    }

    func image(for url: URL, using plexService: PlexService? = nil) async throws -> DuskPlatformImage {
        let cacheKey = url as NSURL
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            if cachedImage.isFresh {
                return cachedImage.image
            }
            memoryCache.removeObject(forKey: cacheKey)
        }

        if url.isFileURL {
            let data = try Data(contentsOf: url)
            guard let image = DuskPlatformImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            memoryCache.setObject(CachedMemoryImage(image: image), forKey: cacheKey)
            return image
        }

        if let task = inFlightTasks[url] {
            return try await task.value.image
        }

        let task = Task<LoadedImage, Error> { [session] in
            let request = URLRequest(
                url: url,
                cachePolicy: .returnCacheDataElseLoad,
                timeoutInterval: 30
            )

            if let cachedResponse = AppImageCache.cachedResponse(for: request),
               let cachedImage = DuskPlatformImage(data: cachedResponse.data) {
                return LoadedImage(
                    image: cachedImage,
                    cachedAt: AppImageCache.cachedAt(for: cachedResponse) ?? .now
                )
            }

            let data: Data
            if let plexService {
                data = try await plexService.imageData(for: url)
            } else {
                let (fetchedData, response) = try await session.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    throw URLError(.badServerResponse)
                }

                data = fetchedData
            }

            guard let image = DuskPlatformImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }

            if let cachedResponse = URLCache.shared.cachedResponse(for: request) {
                AppImageCache.storeCachedResponse(cachedResponse, for: request)
            }
            return LoadedImage(image: image)
        }

        inFlightTasks[url] = task

        do {
            let loadedImage = try await task.value
            memoryCache.setObject(
                CachedMemoryImage(image: loadedImage.image, cachedAt: loadedImage.cachedAt),
                forKey: cacheKey
            )
            inFlightTasks[url] = nil
            return loadedImage.image
        } catch {
            inFlightTasks[url] = nil
            throw error
        }
    }
}

private struct LoadedImage: @unchecked Sendable {
    let image: DuskPlatformImage
    let cachedAt: Date

    init(image: DuskPlatformImage, cachedAt: Date = .now) {
        self.image = image
        self.cachedAt = cachedAt
    }
}

private final class CachedMemoryImage: @unchecked Sendable {
    let image: DuskPlatformImage
    let cachedAt: Date

    init(image: DuskPlatformImage, cachedAt: Date = .now) {
        self.image = image
        self.cachedAt = cachedAt
    }

    var isFresh: Bool {
        Date().timeIntervalSince(cachedAt) <= AppImageCache.maxAge
    }
}
