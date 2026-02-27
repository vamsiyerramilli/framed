import Foundation
import GRDB

/// A group of visually similar photos taken in quick succession.
/// The best photo within the stack is surfaced on top; others are accessible via "see all".
struct Stack: FetchableRecord, PersistableRecord, Codable, Sendable {
    static let databaseTableName = "stacks"

    /// UUID.
    var id: String
    /// FK to photos. The currently elected best photo in this stack.
    /// Note: circular FK with photos.stack_id — enforced at application level, not by SQLite constraint.
    var bestPhotoId: String?
    /// How the best photo was elected: "auto_culling" | "user_selected" | "taste_adjusted".
    /// The pipeline MUST NOT overwrite "user_selected". See Rule 4 in 04-Instructions.md.
    var bestPhotoSource: String?
    var createdAt: Date?
    /// How this stack was formed: "auto" | "manual" | "suggested"
    var formationMethod: String?
    /// The similarity threshold in use when this stack was formed.
    var similarityThresholdUsed: Double?
    /// FK to feed_sections. Nil if the day had fewer than 5 stacks (no sections rendered).
    var feedSectionId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case bestPhotoId = "best_photo_id"
        case bestPhotoSource = "best_photo_source"
        case createdAt = "created_at"
        case formationMethod = "formation_method"
        case similarityThresholdUsed = "similarity_threshold_used"
        case feedSectionId = "feed_section_id"
    }
}
