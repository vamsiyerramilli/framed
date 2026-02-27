import Foundation
import GRDB

/// Manages the GRDB SQLite database for Framed.
/// Stored at ~/Library/Application Support/Framed/framed.db.
/// Thread-safe: DatabasePool handles concurrent reads and serialised writes internally.
final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    private init() {
        // ~/Library/Application Support/Framed/
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first! // Safe: applicationSupportDirectory always exists on macOS
        let dbDir = appSupport.appendingPathComponent("Framed", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        } catch {
            fatalError("[DB] Failed to create database directory at \(dbDir.path): \(error)")
        }

        let dbURL = dbDir.appendingPathComponent("framed.db")
        do {
            dbPool = try DatabasePool(path: dbURL.path)
        } catch {
            fatalError("[DB] Failed to open database at \(dbURL.path): \(error)")
        }

        do {
            try applyMigrations()
            print("[DB] Database ready at \(dbURL.path)")
        } catch {
            fatalError("[DB] Migration failed: \(error)")
        }
    }

    // MARK: - Schema migrations

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Enable WAL mode for concurrent reads alongside pipeline writes
            try db.execute(sql: "PRAGMA journal_mode = WAL")

            // 1. devices — no foreign key dependencies
            try db.create(table: "devices") { t in
                t.primaryKey("id", .text)
                t.column("display_name", .text)
                t.column("device_type", .text)
                t.column("first_seen_at", .datetime).notNull()
            }

            // 2. feed_sections — no foreign key dependencies
            try db.create(table: "feed_sections") { t in
                t.primaryKey("id", .text)
                t.column("day_date", .date).notNull()
                t.column("label", .text).notNull()
                t.column("starts_at", .datetime).notNull()
                t.column("ends_at", .datetime).notNull()
                t.column("computed_at", .datetime).notNull()
            }

            // 3. stacks — best_photo_id references photos (circular ref).
            //    The FK constraint on best_photo_id is intentionally omitted to break the
            //    photos ↔ stacks circular dependency. Application logic enforces integrity.
            try db.create(table: "stacks") { t in
                t.primaryKey("id", .text)
                t.column("best_photo_id", .text) // No FK — circular reference with photos
                t.column("best_photo_source", .text)
                t.column("created_at", .datetime)
                t.column("formation_method", .text)
                t.column("similarity_threshold_used", .double)
                t.column("feed_section_id", .text).references("feed_sections")
            }

            // 4. photos — references devices and stacks
            try db.create(table: "photos") { t in
                t.primaryKey("id", .text)
                t.column("file_path", .text).notNull()
                t.column("source_device_id", .text).references("devices")
                t.column("captured_at", .datetime).notNull()
                t.column("ingested_at", .datetime).notNull()
                t.column("format", .text)
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("file_size_bytes", .integer)
                t.column("stack_id", .text).references("stacks")
                t.column("similarity_score", .double)
                t.column("vector_valid", .boolean).notNull().defaults(to: false)
                t.column("review_status", .text).notNull().defaults(to: "unseen")
                t.column("exif_json", .text)
            }
            try db.create(indexOn: "photos", columns: ["captured_at"])
            try db.create(indexOn: "photos", columns: ["stack_id"])
            try db.create(indexOn: "photos", columns: ["review_status"])

            // 5. feature_vectors — references photos
            try db.create(table: "feature_vectors") { t in
                t.primaryKey("photo_id", .text).references("photos")
                t.column("perceptual_hash", .blob).notNull()
                t.column("feature_vector", .blob).notNull()
                t.column("computed_at", .datetime).notNull()
            }

            // 6. stack_edits — references photos and stacks
            try db.create(table: "stack_edits") { t in
                t.primaryKey("id", .text)
                t.column("photo_id", .text).notNull().references("photos")
                t.column("stack_id", .text).notNull().references("stacks")
                t.column("action", .text).notNull()
                t.column("actioned_at", .datetime).notNull()
                t.column("previous_stack_id", .text)
            }

            // 7. edits — references photos
            try db.create(table: "edits") { t in
                t.primaryKey("id", .text)
                t.column("photo_id", .text).notNull().references("photos")
                t.column("created_at", .datetime)
                t.column("edit_type", .text)
                t.column("parameters_json", .text)
                t.column("is_active", .boolean)
                t.column("source", .text)
            }

            // 8. taste_signals — references photos and stacks (both nullable)
            try db.create(table: "taste_signals") { t in
                t.primaryKey("id", .text)
                t.column("photo_id", .text).references("photos")
                t.column("stack_id", .text).references("stacks")
                t.column("signal_type", .text)
                t.column("recorded_at", .datetime)
                t.column("metadata_json", .text)
            }
        }

        try migrator.migrate(dbPool)
    }
}
