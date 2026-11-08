import SwiftUI
import UIKit
import ImageIO

/// Bounded, profile-scoped memory cache. Networking uses PlexService's existing
/// authenticated image pipeline; token-bearing URLs never reach diagnostics.
@MainActor
@Observable
final class TVArtworkModel {
    var image: UIImage?
    private var loadGeneration = 0
    private static let cache: NSCache<NSString, UIImage> = {
        let value = NSCache<NSString, UIImage>()
        value.totalCostLimit = 32 * 1024 * 1024
        value.countLimit = 120
        return value
    }()

    func load(service: PlexService, path: String?, serverID: String?, width: Int, height: Int) async {
        loadGeneration += 1
        let generation = loadGeneration
        image = nil
        guard let url = service.imageURL(for: path, serverID: serverID, width: width, height: height) else { return }
        let key = "\(service.activeProfileID ?? "-")|\(serverID ?? "-")|\(url.absoluteString)" as NSString
        if let cached = Self.cache.object(forKey: key) { image = cached; return }
        guard let data = try? await service.imageData(for: url), !Task.isCancelled,
              generation == loadGeneration else { return }
        let decoded = await TVArtworkDecoder.shared.decode(data, maxPixelSize: max(width, height))
        guard !Task.isCancelled, generation == loadGeneration, let decoded else { return }
        Self.cache.setObject(decoded, forKey: key,
            cost: decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        image = decoded
    }
}

/// A serial executor keeps image decompression off the UI actor and avoids a
/// burst of concurrent bitmap allocations when a shelf first becomes visible.
actor TVArtworkDecoder {
    static let shared = TVArtworkDecoder()

    func decode(_ data: Data, maxPixelSize: Int) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        return Self.thumbnail(data, maxPixelSize: maxPixelSize)
    }

    nonisolated static func thumbnail(_ data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0 else { return nil }
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }
    }
}

struct TVArtwork: View {
    let service: PlexService
    let path: String?
    let serverID: String?
    var width: CGFloat = 220
    var height: CGFloat = 330
    var cornerRadius: CGFloat = 16
    var showsPlaceholder = true
    var contentMode: ContentMode = .fill
    @State private var model = TVArtworkModel()

    var body: some View {
        ZStack {
            if showsPlaceholder { Rectangle().fill(.quaternary) }
            else { Color.black }
            if let image = model.image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if showsPlaceholder {
                Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height).clipped().clipShape(.rect(cornerRadius: cornerRadius))
        .task(id: "\(service.activeProfileID ?? "-")|\(serverID ?? "-")|\(path ?? "-")|\(width)x\(height)") {
            await model.load(service: service, path: path, serverID: serverID,
                width: Int(width), height: Int(height))
        }
    }
}

struct TVMediaCard: View {
    let service: PlexService
    let item: PlexItem
    var landscape = false
    var select: (() -> Void)?
    private var width: CGFloat { landscape ? 340 : 220 }
    private var height: CGFloat { landscape ? 191 : 330 }

    var body: some View {
        Group {
            if let select {
                Button(action: select) { label }
            } else {
                NavigationLink { TVMediaView(service: service, itemID: item.id) } label: { label }
            }
        }
        .buttonStyle(.card)
        .accessibilityLabel([item.grandparentTitle, item.title].compactMap { $0 }.joined(separator: ", "))
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 12) {
            TVArtwork(service: service, path: landscape ? item.preferredLandscapePath : item.preferredPosterPath,
                serverID: item.serverID, width: width, height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .overlay(alignment: .bottom) {
                    if let progress = item.posterProgress {
                        GeometryReader { geometry in
                            Rectangle().fill(.white.opacity(0.85))
                                .frame(width: geometry.size.width * min(1, max(0, progress)))
                        }.frame(height: 5).clipShape(.capsule).padding(12)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.isWatched {
                        Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.65)).padding(12)
                    }
                }
            Text(item.type == .episode ? item.continueWatchingDisplayTitle : item.title)
                .font(.callout.weight(.semibold)).lineLimit(2)
                .frame(height: 72, alignment: .topLeading)
            Text(item.standardPosterSubtitle ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(width: width, alignment: .leading)
    }
}

struct TVMediaShelf: View {
    let service: PlexService
    let title: String
    let items: [PlexItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 28) {
                Text(title).font(.title2.bold())
                TVDeckRule()
            }.padding(.horizontal, TVDeckLayout.horizontalInset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TVDeckLayout.cardSpacing) {
                    ForEach(items) { TVMediaCard(service: service, item: $0) }
                }.padding(.horizontal, TVDeckLayout.horizontalInset).padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
        .modifier(TVDeckBay())
        .focusSection()
    }
}

extension PlexItem {
    var isTVBrowsable: Bool { [.movie, .show, .season, .episode, .clip].contains(type) }
}
