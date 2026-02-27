import Foundation

// MARK: - In-memory feed data model
// Matches PRD Section 3.4 exactly. These types are never persisted to the database;
// they are constructed from DB query results each session.

/// The top-level grouping in the feed. Represents one calendar day (with post-midnight rollback
/// applied — photos taken 00:00–03:59 are attached to the preceding day).
struct FeedDay: Identifiable {
    /// Midnight of the logical calendar day in the user's local time zone.
    var id: Date { date }
    let date: Date
    /// Human-readable header label: "Today", "Yesterday", or "EEEE, d MMMM" (e.g. "Wednesday, 26 February").
    let label: String
    /// Time-of-day sections within the day, in chronological order (earliest first).
    let sections: [FeedSection]
}

/// A contiguous shooting session within a day, derived from natural gaps in shooting frequency.
/// Only rendered as a visual header when the parent day has 5+ photos and there are multiple sections.
struct FeedSection: Identifiable {
    var id: String { timeOfDayLabel }
    /// Human-readable label: "Morning" | "Afternoon" | "Evening" | "Night" | "Early morning"
    let timeOfDayLabel: String
    /// Photos in this section, in ascending captured_at order.
    let items: [FeedItem]
}

/// A single item in the feed. In Slice 2, only individual photos (no stacking).
/// The .stack case is added in Slice 3.
enum FeedItem: Identifiable {
    case photo(Photo, deviceName: String?)

    var id: String {
        switch self {
        case .photo(let p, _): return "photo-\(p.id)"
        }
    }

    var primaryPhoto: Photo {
        switch self {
        case .photo(let p, _): return p
        }
    }

    var capturedAt: Date { primaryPhoto.capturedAt }

    var deviceName: String? {
        switch self {
        case .photo(_, let name): return name
        }
    }
}
