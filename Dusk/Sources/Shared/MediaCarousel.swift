import SwiftUI

/// Reusable horizontal carousel with a section title.
struct MediaCarousel<Content: View>: View {
    let title: String
    let horizontalPadding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        horizontalPadding: CGFloat = DuskPosterMetrics.carouselHorizontalPadding,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.horizontalPadding = horizontalPadding
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DuskPosterMetrics.carouselSectionSpacing) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.primary.opacity(0.65))
                    .frame(width: 3, height: 18)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DuskFont.sectionHeader(style: .title3.bold()))
                    .tracking(0.4)
                    .foregroundStyle(Color.primary)
                Rectangle()
                    .fill(.primary.opacity(0.10))
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DuskPosterMetrics.carouselItemSpacing) {
                    content()
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, DuskPosterMetrics.carouselBottomPadding)
            }

        }
    }
}
