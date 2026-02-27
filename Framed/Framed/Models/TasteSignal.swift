import Foundation
import GRDB

/// An observational record of user behaviour, used to personalise culling and edits over time.
/// Signal capture is active from Slice 1; learning activation is post-V1.
/// Nothing in V1 reads from this table — it accumulates data for future use.
struct TasteSignal: FetchableRecord, PersistableRecord, Codable, Sendable {
    static let databaseTableName = "taste_signals"

    /// UUID.
    var id: String
    /// FK to photos. Nil if the signal is stack-level.
    var photoId: String?
    /// FK to stacks. Nil if the signal is photo-level.
    var stackId: String?
    /// "kept" | "discarded" | "edit_accepted" | "edit_undone" | "stack_modified" | "best_photo_changed"
    var signalType: String?
    var recordedAt: Date?
    /// Extra context for this signal stored as JSON.
    var metadataJson: String?

    enum CodingKeys: String, CodingKey {
        case id
        case photoId = "photo_id"
        case stackId = "stack_id"
        case signalType = "signal_type"
        case recordedAt = "recorded_at"
        case metadataJson = "metadata_json"
    }
}
