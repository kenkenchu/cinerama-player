import SwiftUI

struct PosterNavigationCard<ContextMenuContent: View>: View {
    let route: AppNavigationRoute
    let imageURL: URL?
    let title: String
    var subtitle: String?
    var progress: Double?
    var width: CGFloat = 130
    var imageAspectRatio: CGFloat = 2.0 / 3.0
    var showsPlayOverlay = false
    var availabilityBadge: String? = nil
    var isDimmed = false
    var isWatched = false
    @ViewBuilder let contextMenuContent: () -> ContextMenuContent

    var body: some View {
        NavigationLink(value: route) {
            PosterCard(
                imageURL: imageURL,
                title: title,
                subtitle: subtitle,
                progress: progress,
                width: width,
                imageAspectRatio: imageAspectRatio,
                showsPlayOverlay: showsPlayOverlay,
                availabilityBadge: availabilityBadge,
                isDimmed: isDimmed,
                isWatched: isWatched,
                showsPointerFeedback: true
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Open details for \(title)")

        .contextMenu {
            contextMenuContent()
        }
    }
}

extension PosterNavigationCard where ContextMenuContent == EmptyView {
    init(
        route: AppNavigationRoute,
        imageURL: URL?,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        width: CGFloat = 130,
        imageAspectRatio: CGFloat = 2.0 / 3.0,
        showsPlayOverlay: Bool = false,
        availabilityBadge: String? = nil,
        isDimmed: Bool = false,
        isWatched: Bool = false
    ) {
        self.route = route
        self.imageURL = imageURL
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.width = width
        self.imageAspectRatio = imageAspectRatio
        self.showsPlayOverlay = showsPlayOverlay
        self.availabilityBadge = availabilityBadge
        self.isDimmed = isDimmed
        self.isWatched = isWatched
        self.contextMenuContent = { EmptyView() }
    }
}

struct PosterActionCard<ContextMenuContent: View>: View {
    let action: () -> Void
    let imageURL: URL?
    let title: String
    var subtitle: String?
    var progress: Double?
    var width: CGFloat = 130
    var imageAspectRatio: CGFloat = 2.0 / 3.0
    var showsPlayOverlay = false
    var availabilityBadge: String? = nil
    var isDimmed = false
    @ViewBuilder let contextMenuContent: () -> ContextMenuContent

    var body: some View {
        Button(action: action) {
            PosterCard(
                imageURL: imageURL,
                title: title,
                subtitle: subtitle,
                progress: progress,
                width: width,
                imageAspectRatio: imageAspectRatio,
                showsPlayOverlay: showsPlayOverlay,
                availabilityBadge: availabilityBadge,
                isDimmed: isDimmed,
                showsPointerFeedback: true
            )
        }
        .buttonStyle(.plain)

        .contextMenu {
            contextMenuContent()
        }
    }
}

extension PosterActionCard where ContextMenuContent == EmptyView {
    init(
        action: @escaping () -> Void,
        imageURL: URL?,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        width: CGFloat = 130,
        imageAspectRatio: CGFloat = 2.0 / 3.0,
        showsPlayOverlay: Bool = false,
        availabilityBadge: String? = nil,
        isDimmed: Bool = false
    ) {
        self.action = action
        self.imageURL = imageURL
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.width = width
        self.imageAspectRatio = imageAspectRatio
        self.showsPlayOverlay = showsPlayOverlay
        self.availabilityBadge = availabilityBadge
        self.isDimmed = isDimmed
        self.contextMenuContent = { EmptyView() }
    }
}
