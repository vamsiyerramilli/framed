import Foundation
import GRDB

// MARK: - PhotoWithDevice

/// A photo row joined with its optional device display name.
/// Decoded from raw SQL via init(row:) — avoids modifying the Slice 1 Photo model.
struct PhotoWithDevice: FetchableRecord {
    let photo: Photo
    /// `devices.display_name` — nil when no device record or device has no name.
    let deviceName: String?

    init(row: Row) throws {
        photo = try Photo(row: row)
        deviceName = row["device_display_name"]
    }
}

// MARK: - FeedRepository

final class FeedRepository {
    static let shared = FeedRepository()

    private let db: DatabaseManager
    private let calendar: Calendar

    init(db: DatabaseManager = .shared, calendar: Calendar = .current) {
        self.db = db
        self.calendar = calendar
    }

    // MARK: - Queries

    /// Fetches up to 50 photos (newest first) with their device name.
    /// Pass `cursor`/`cursorId` to page: returns photos strictly older than the cursor row.
    /// Pass `nil` for the initial load (no cursor).
    func fetchPage(cursor: Date?, cursorId: String?) async throws -> [PhotoWithDevice] {
        try await db.dbPool.read { db in
            var sql = """
                SELECT photos.*, devices.display_name AS device_display_name
                FROM photos
                LEFT JOIN devices ON photos.source_device_id = devices.id
                """

            var args: StatementArguments = [:]

            if let cursor, let cursorId {
                // Keyset cursor: exclude rows at or above (cursor, cursorId) in (DESC, DESC) order.
                // Equivalent to: rows that come *after* (cursor, cursorId) in DESC order.
                sql += """

                    WHERE (photos.captured_at < :cursor)
                       OR (photos.captured_at = :cursor AND photos.id < :cursorId)
                    """
                args = ["cursor": cursor, "cursorId": cursorId]
            }

            sql += """

                ORDER BY photos.captured_at DESC, photos.id DESC
                LIMIT 50
                """

            return try PhotoWithDevice.fetchAll(db, sql: sql, arguments: args)
        }
    }

    // MARK: - Feed construction

    /// Converts a flat array of rows (as returned by `fetchPage`, newest-first from DB)
    /// into a `[FeedDay]` array sorted with the most recent day first.
    func buildFeed(from rows: [PhotoWithDevice]) -> [FeedDay] {
        guard !rows.isEmpty else { return [] }

        let today = calendar.startOfDay(for: Date())

        // Group by logical date (post-midnight rollback applied)
        var byDate: [Date: [PhotoWithDevice]] = [:]
        for row in rows {
            let logicalDay = logicalDate(for: row.photo.capturedAt)
            byDate[logicalDay, default: []].append(row)
        }

        // Sort dates descending, build FeedDays
        return byDate.keys.sorted(by: >).map { date in
            var dayRows = byDate[date]!
            // Sort ascending within each day (for section derivation and display)
            dayRows.sort {
                if $0.photo.capturedAt != $1.photo.capturedAt {
                    return $0.photo.capturedAt < $1.photo.capturedAt
                }
                return $0.photo.id < $1.photo.id
            }

            let sections = deriveSections(from: dayRows)
            let label = dayLabel(for: date, today: today)
            return FeedDay(date: date, label: label, sections: sections)
        }
    }

    // MARK: - ValueObservation

    /// Lightweight observation of total photo count.
    /// Used by FeedViewModel to detect mid-session ingests without re-running the full query.
    func photoCountObservation() -> ValueObservation<ValueReducers.Fetch<Int>> {
        ValueObservation.tracking { db in try Photo.fetchCount(db) }
    }
}

// MARK: - Section derivation (internal helpers)

extension FeedRepository {

    /// Returns the logical calendar day for a photo, applying the post-midnight rollback:
    /// photos captured between 00:00 and 03:59 are assigned to the preceding calendar day.
    func logicalDate(for capturedAt: Date) -> Date {
        let hour = calendar.component(.hour, from: capturedAt)
        let calendarDay = calendar.startOfDay(for: capturedAt)
        if hour < 4 {
            return calendar.date(byAdding: .day, value: -1, to: calendarDay)!
        }
        return calendarDay
    }

    /// Splits a day's photos (already sorted ascending) into `FeedSection` values
    /// based on natural gaps in shooting activity (90-minute threshold).
    func deriveSections(from rows: [PhotoWithDevice]) -> [FeedSection] {
        guard !rows.isEmpty else { return [] }

        let gapThreshold: TimeInterval = 90 * 60

        // Build raw groups separated by gaps
        var groups: [[PhotoWithDevice]] = [[rows[0]]]
        for i in 1..<rows.count {
            let gap = rows[i].photo.capturedAt.timeIntervalSince(rows[i - 1].photo.capturedAt)
            if gap > gapThreshold {
                groups.append([])
            }
            groups[groups.count - 1].append(rows[i])
        }

        // Map each group to a FeedSection with a time-of-day label
        return groups.map { group in
            let label = timeOfDayLabel(for: group[0].photo.capturedAt)
            let items = group.map { FeedItem.photo($0.photo, deviceName: $0.deviceName) }
            return FeedSection(timeOfDayLabel: label, items: items)
        }
    }

    /// Time-of-day label for a given capture time, based on clock hour.
    func timeOfDayLabel(for date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 0..<6:   return "Early morning"
        case 6..<12:  return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default:      return "Night"
        }
    }

    /// Human-readable day header label.
    func dayLabel(for date: Date, today: Date) -> String {
        if calendar.isDateInToday(date)     { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }
}
