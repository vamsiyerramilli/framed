import Foundation
import GRDB

/// A camera or phone that has contributed photos to Framed.
/// Identified by EXIF model string on first ingest; subsequent photos from the same model reuse the record.
struct Device: FetchableRecord, PersistableRecord, Codable, Sendable {
    static let databaseTableName = "devices"

    /// UUID generated on first sighting of this device.
    var id: String
    /// Human-readable name derived from EXIF model string (e.g. "FUJIFILM X-T5", "iPhone 15 Pro").
    var displayName: String?
    /// Broad category: "camera" | "phone" | "scanner" etc.
    var deviceType: String?
    /// When this device was first seen by Framed.
    var firstSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case deviceType = "device_type"
        case firstSeenAt = "first_seen_at"
    }
}
