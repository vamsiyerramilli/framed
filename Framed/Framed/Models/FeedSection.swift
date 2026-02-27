import Foundation
import GRDB

/// A pre-computed time-of-day section within a day in the review feed.
/// Sections are derived from natural gaps in shooting activity (not fixed clock buckets).
/// Only rendered when a day has 5 or more stacks.
struct FeedSection: FetchableRecord, PersistableRecord, Codable, Sendable {
    static let databaseTableName = "feed_sections"

    /// UUID.
    var id: String
    /// Calendar date for this section, adjusted so post-midnight photos attach to the preceding evening.
    var dayDate: Date
    /// Human-readable label: "Morning" | "Afternoon" | "Evening" | "Night" | "Early morning"
    var label: String
    /// captured_at of the first stack in this section.
    var startsAt: Date
    /// captured_at of the last stack in this section.
    var endsAt: Date
    /// When this section boundary was computed. Recomputed if new photos arrive for the same day.
    var computedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case dayDate = "day_date"
        case label
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case computedAt = "computed_at"
    }
}
