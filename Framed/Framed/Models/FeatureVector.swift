import Foundation
import GRDB

/// Vision.framework feature data for a photo. Computed in Pipeline Stage 3 (Analysis).
/// Stored separately from photos for query performance — the large BLOB is only read when stacking runs.
struct FeatureVector: FetchableRecord, PersistableRecord, Codable, Sendable {
    static let databaseTableName = "feature_vectors"

    /// FK to photos (also the primary key).
    var photoId: String
    /// 8-byte dHash (difference hash) for fast Hamming-distance pre-filter before cosine similarity.
    var perceptualHash: Data
    /// 2048 × float32 Vision.framework VNFeaturePrintObservation, stored as little-endian BLOB.
    var featureVector: Data
    var computedAt: Date

    enum CodingKeys: String, CodingKey {
        case photoId = "photo_id"
        case perceptualHash = "perceptual_hash"
        case featureVector = "feature_vector"
        case computedAt = "computed_at"
    }
}
