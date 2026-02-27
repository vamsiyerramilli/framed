import SwiftUI

/// A single photo card in the review feed.
/// Shows: thumbnail (lazily loaded), device tag, and unseen indicator.
struct PhotoCard: View {
    let item: FeedItem

    @State private var thumbnail: CGImage? = nil

    private var photo: Photo { item.primaryPhoto }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // MARK: Thumbnail / placeholder
            Group {
                if let thumb = thumbnail {
                    Image(decorative: thumb, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                }
            }
            .clipped()

            // MARK: Bottom gradient scrim for label readability
            LinearGradient(
                colors: [.clear, .black.opacity(0.50)],
                startPoint: .center,
                endPoint: .bottom
            )

            // MARK: Bottom row: device tag + unseen indicator
            HStack(alignment: .bottom) {
                if let name = item.deviceName {
                    DeviceTag(name: name)
                }
                Spacer()
                if photo.reviewStatus == "unseen" {
                    UnseenDot()
                }
            }
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // Load thumbnail in background; auto-cancels when the card leaves the viewport.
        .task(id: photo.filePath) {
            thumbnail = await ThumbnailCache.shared.thumbnail(for: photo.filePath)
        }
    }
}

// MARK: - Sub-views

private struct DeviceTag: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

private struct UnseenDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 8, height: 8)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}
