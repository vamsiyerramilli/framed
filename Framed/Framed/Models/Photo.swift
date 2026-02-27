import Foundation
import GRDB

/// A single photo record in Framed's managed storage.
/// The `id` is the SHA-256 content hash — immutable after ingest.
struct Photo: FetchableRecord, PersistableRecord, Codable, Sendable {
    static let databaseTableName = "photos"

    /// SHA-256 content hash in lowercase hex. Primary key and canonical identifier.
    var id: String
    /// Absolute path to the original file in Framed storage (~/Pictures/Framed/…). Never modified after ingest.
    var filePath: String
    /// FK to devices table. Nil if the source device could not be identified.
    var sourceDeviceId: String?
    /// Capture timestamp from EXIF DateTimeOriginal. Falls back to file modification date if EXIF is absent.
    var capturedAt: Date
    /// When Framed first processed this file.
    var ingestedAt: Date
    /// File format: RAF, DNG, HEIC, JPEG, etc.
    var format: String?
    var width: Int?
    var height: Int?
    var fileSizeBytes: Int?
    /// FK to stacks table. Nil if the photo is not in any stack.
    var stackId: String?
    /// Cosine similarity score against the stack centroid at time of stack assignment.
    var similarityScore: Double?
    /// False if the feature vector has not yet been computed (Analysis stage pending).
    var vectorValid: Bool
    /// Review state: "unseen" | "kept" | "discarded"
    var reviewStatus: String
    /// Full EXIF metadata stored as JSON for reference.
    var exifJson: String?

    enum CodingKeys: String, CodingKey {
        case id
        case filePath = "file_path"
        case sourceDeviceId = "source_device_id"
        case capturedAt = "captured_at"
        case ingestedAt = "ingested_at"
        case format
        case width
        case height
        case fileSizeBytes = "file_size_bytes"
        case stackId = "stack_id"
        case similarityScore = "similarity_score"
        case vectorValid = "vector_valid"
        case reviewStatus = "review_status"
        case exifJson = "exif_json"
    }
}
