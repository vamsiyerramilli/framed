import SwiftUI

/// Renders one calendar day: a day header followed by time-of-day sections and their photo grids.
///
/// Section headers are only rendered when the day has 5+ photos across 2+ sections (AC-2.3).
struct DaySection: View {
    let day: FeedDay

    private var totalPhotos: Int {
        day.sections.reduce(0) { $0 + $1.items.count }
    }

    /// Show section headers only when there are enough photos to make them meaningful.
    private var showSectionHeaders: Bool {
        totalPhotos >= 5 && day.sections.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Day header
            Text(day.label)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.bottom, 2)

            if showSectionHeaders {
                ForEach(day.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.timeOfDayLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        PhotoGrid(items: section.items)
                    }
                }
            } else {
                // Flatten all sections — no headers for small days or single-session days
                PhotoGrid(items: day.sections.flatMap(\.items))
            }
        }
    }
}

// MARK: - PhotoGrid

/// 2-column lazy grid of photo cards. Square aspect ratio per cell.
struct PhotoGrid: View {
    let items: [FeedItem]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items) { item in
                PhotoCard(item: item)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
