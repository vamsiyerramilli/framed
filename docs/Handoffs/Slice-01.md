# Slice 1 Handoff — Foundation

**Status:** Complete (9/11 AC verified; 2 parked — hardware-gated)

---

## Acceptance Criteria

- AC-1.1 — App launches: ✓
- AC-1.2 — SD card detection: ⏸ Parked — requires physical SD card. Test alongside AC-1.8.
- AC-1.3 — File enumeration: ✓ — 5 HEIC files discovered and processed
- AC-1.4 — Hash computation: ✓ — SHA-256 verified via `shasum -a 256`, matches `photos.id`
- AC-1.5 — File move: ✓ — files at `~/Pictures/Framed/YYYY/MM/DD/`, absent from source
- AC-1.6 — DB record creation: ✓ — all fields populated, `review_status = unseen`
- AC-1.7 — Deduplication: ✓ — SHA-256 of moved files matches DB; re-ingest would skip (verified automatically)
- AC-1.8 — Device record: ⏸ Parked — test images lack camera EXIF. Will populate on real SD card ingest alongside AC-1.2.
- AC-1.9 — Background processing: ✓ — actor executor confirmed, UI remained responsive
- AC-1.10 — Original file intact: ✓ — SHA-256 at new location matches `photos.id` for all 5 files
- AC-1.11 — Schema completeness: ✓ — all 8 tables verified via `.schema`

---

## What Was Built

- **`Database/DatabaseManager.swift`** — GRDB `DatabasePool` at `~/Library/Application Support/Framed/framed.db`; all 8 tables created in migration v1; WAL mode; 3 indexes on `photos`
- **`Models/`** — 8 GRDB record types (`Photo`, `Device`, `Stack`, `StackEdit`, `FeatureVector`, `PhotoEdit`, `TasteSignal`, `FeedSection`) using `Codable` + `CodingKeys` for snake_case mapping
- **`Pipeline/IngestManager.swift`** — Swift actor; DiskArbitration SD card detection; sequential file enumeration; SHA-256 via streaming CryptoKit; EXIF extraction via ImageIO; file move; device lookup/creation; database write
- **`Extensions/URL+SHA256.swift`** — streaming SHA-256 in 64KB chunks (avoids loading full RAW files into memory)
- **`FramedApp.swift`** — DB initialised on launch; DA monitoring started via `.task`; `File → Test Ingest from Folder…` command (⌘⇧I)

## Decisions Made This Slice

- **App Sandbox disabled** — required for DiskArbitration file access and `FileManager.moveItem`. Personal use app, not App Store.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` removed** — auto-added by Xcode template; incompatible with background pipeline actors. Free functions and model types are correctly nonisolated by default.
- **`triggerTestIngest(from:)` added to IngestManager** — permanent development affordance. Exposes pipeline for testing without SD card hardware. Documented in `03-Slice-Definitions.md`.
- **`test-images/` in `.gitignore`** — local test assets, not version-controlled.

---

## Next Session Starts With

**Slice 2 — Feed.** Goal: read from the database and render the review feed.

First task: implement the `FeedDay` / `FeedSection` / `FeedItem` data model and the initial database query (keyset pagination on `captured_at`, 2 most recent days). The 5 ingested HEIC records in the database serve as real test data for feed rendering.
