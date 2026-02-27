import Foundation
import GRDB

/// An operational log entry recording a manual stack management action by the user.
/// Every add / remove / restack is recorded here and also written to taste_signals.
struct StackEdit: FetchableRecord, PersistableRecord, Codable, Sendable {
    static let databaseTableName = "stack_edits"

    /// UUID.
    var id: String
    /// FK to photos.
    var photoId: String
    /// FK to stacks — the target stack for this action.
    var stackId: String
    /// "added" | "removed" | "restacked"
    var action: String
    var actionedAt: Date
    /// Source stack ID if action == "restacked".
    var previousStackId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case photoId = "photo_id"
        case stackId = "stack_id"
        case action
        case actionedAt = "actioned_at"
        case previousStackId = "previous_stack_id"
    }
}
