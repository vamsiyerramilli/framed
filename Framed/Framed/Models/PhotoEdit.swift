import Foundation
import GRDB

/// A non-destructive edit applied to a photo. Full edit state stored as JSON.
/// Only one edit record per photo has `isActive = true` at any time.
/// Named PhotoEdit to avoid conflict with Swift's built-in `Edit` protocol.
struct PhotoEdit: FetchableRecord, PersistableRecord, Codable, Sendable {
    static let databaseTableName = "edits"

    /// UUID.
    var id: String
    /// FK to photos.
    var photoId: String
    var createdAt: Date?
    /// "theme" | "adjustment" | "geometry" | "prompt"
    var editType: String?
    /// Full edit state as JSON (see PRD Section 2.6 for schema).
    var parametersJson: String?
    /// True for the current active edit chain on this photo.
    var isActive: Bool?
    /// "user" | "suggested"
    var source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case photoId = "photo_id"
        case createdAt = "created_at"
        case editType = "edit_type"
        case parametersJson = "parameters_json"
        case isActive = "is_active"
        case source
    }
}
