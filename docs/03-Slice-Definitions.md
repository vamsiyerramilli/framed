# Framed — Slice-by-Slice Implementation Plan

**Type:** Detailed build reference for each Claude Code session  
**Read alongside:** `01-PRD.md` and `02-Implementation-Plan.md`

Each slice section contains: goal, scope, technical approach, acceptance criteria, edge cases, and what NOT to build. The acceptance criteria are the QA checklist — every item must pass before the slice is considered done.

---

## Slice 1 — Foundation

**Goal:** The SD card to database path. Nothing visual. The pipeline runs.

**One-line test:** Plug in an SD card. A photo record appears in the database.

---

### Scope

- Xcode project creation: SwiftUI Mac app target, Swift Package Manager dependencies (GRDB)
- Full database schema creation with GRDB migrations (all 8 tables, all columns, all indexes — exactly as specified in PRD Section 4)
- DiskArbitration framework integration: detect SD card mount event
- File discovery: enumerate image files on mounted SD card (RAF, HEIC, JPEG, DNG)
- SHA-256 hash computation per file
- Deduplication check: skip if hash already in database
- File move to `~/Pictures/Framed/` (not copy)
- EXIF extraction: `captured_at`, format, dimensions, file size, device info
- Write photo record to `photos` table with `review_status = unseen`
- Write or retrieve device record in `devices` table
- Background processing: ingest runs on a background Task, never on main thread
- Basic logging: pipeline stages logged to console

### Out of scope for this slice

- Any UI beyond the app shell launching
- Analysis (featurePrint) — that is Slice 3
- Stacking — Slice 3
- Culling — Slice 4
- Watched folder source — Slice 8
- Photos library source — Slice 8

---

### Technical Approach

**GRDB setup:** Use `DatabaseMigrator` for schema versioning. All 8 tables created in migration v1. Schema must exactly match PRD Section 4 — no deviations.

**DiskArbitration:** Register a `DADiskAppearedCallback` on app launch. Filter for volumes that appear to be SD cards (FAT32/exFAT formatted removable media containing DCIM folder). Emit the DCIM path into an ingest job queue (a Swift `AsyncStream` or actor-based queue).

**Ingest sequencing:** Process files sequentially within a batch (not concurrent) to avoid file system races. Use Swift structured concurrency — a single Task consumes from the queue.

**SHA-256:** Use `CryptoKit.SHA256` on the raw file bytes. Store as lowercase hex string. This is the `photos.id` primary key.

**EXIF extraction:** Use `ImageIO` framework (`CGImageSourceCopyPropertiesAtIndex`). Extract at minimum: `DateTimeOriginal` (→ `captured_at`), `PixelXDimension`/`PixelYDimension`, `FileSize` (from file attributes), model string (→ device name). Store full EXIF dict as JSON in `exif_json`.

**File move:** Use `FileManager.moveItem(at:to:)`. Create destination directory structure if needed (`~/Pictures/Framed/YYYY/MM/DD/`). On move failure, log and skip — do not crash.

**Device identification:** Match by EXIF model string. If model not seen before, create new `devices` record with a UUID. On subsequent SD card insertions from the same camera, match to existing device record.

---

### Testing Approach

**AC-1.2 requires physical hardware.** All other criteria (AC-1.3 through AC-1.11) can be verified without an SD card using the **"File → Test Ingest from Folder…"** menu item (⌘⇧I). This triggers the full ingest pipeline against any folder of image files on disk, bypassing DiskArbitration detection entirely. Create a test folder with a few JPEG or RAW files and use this menu item to drive all pipeline verification.

**Decision recorded:** A `triggerTestIngest(from:)` method was added to `IngestManager` and exposed via a macOS menu command (`File → Test Ingest from Folder…`, ⌘⇧I). This is a permanent development affordance — it enables pipeline testing without hardware in any future slice that extends the pipeline.

---

### Acceptance Criteria

**AC-1.1 — App launches**
The app launches on macOS without crash or error. The main window appears.

**AC-1.2 — SD card detection** *(requires hardware — test separately)*
Inserting an SD card (with a DCIM folder) triggers detection within 3 seconds. Log message confirms detection.

**AC-1.3 — File enumeration**
All image files in the DCIM folder are discovered. At minimum: RAF, HEIC, JPEG, DNG. Non-image files (thumbnails, video) are ignored gracefully.

**AC-1.4 — Hash computation**
SHA-256 hash is computed for each file. Verify by computing independently with `shasum -a 256` on the command line and comparing.

**AC-1.5 — File move**
Files are moved to `~/Pictures/Framed/`. Verify source location no longer contains the files after ingest. Verify destination contains the files.

**AC-1.6 — Database record creation**
Each ingested photo has a record in the `photos` table with: correct `id` (SHA-256 hash), correct `file_path` (new location), `review_status = unseen`, non-null `captured_at` (from EXIF), non-null `ingested_at`.

**AC-1.7 — Deduplication**
Re-inserting the same SD card results in zero new records. Log confirms each file was identified as a duplicate and skipped. No files are moved again.

**AC-1.8 — Device record**
A record exists in `devices` for the camera that shot the photos. `display_name` is populated from EXIF model string.

**AC-1.9 — Background processing**
Ingest does not block the main thread. The app remains responsive during ingest (verify by attempting to interact with the window during a large batch ingest).

**AC-1.10 — Original file intact**
After ingest, the hash of the file at its new location matches the hash computed before move. The file has not been modified.

**AC-1.11 — Schema completeness**
All 8 tables exist in the database with all columns as specified in PRD Section 4. Verify via `sqlite3` CLI: `.schema` output matches spec.

---

### Edge Cases to Handle

- SD card with no DCIM folder — detect and skip gracefully, log
- SD card already fully ingested (all hashes present) — skip all, log summary, no errors
- File that cannot be read (permissions, corruption) — skip individual file, continue batch, log
- EXIF missing `DateTimeOriginal` — fall back to file modification date for `captured_at`
- Move fails (disk full, permissions) — log error, do not mark record as ingested, retry on next launch
- App quit mid-ingest — on next launch, incomplete ingest detected via missing records; resume from last committed record

---

## Slice 2 — Feed

**Goal:** See your photos in a feed.

**One-line test:** After Slice 1, open the app and see your photos grouped by day, in the order they were taken.

---

### Scope

- `FeedDay` / `FeedSection` / `FeedItem` data model (exactly as specified in PRD Section 3.4)
- Database query: keyset pagination on `captured_at`, initial load of 2 most recent days
- Time-of-day section label derivation in Swift layer (activity-based, clock as guardrail — see PRD Section 3.4)
- Post-midnight photo rollback: photos taken after midnight attach to the preceding day's evening session
- Day headers with date labels
- Section headers (only rendered when day has 5+ stacks — for Slice 2 with no stacking yet, use 5+ photos)
- Photo thumbnail rendering: lazy loading, cached, never blocks scroll
- Device tag on each photo card
- Unseen visual indicator on each photo card (subtle, not demanding)
- GRDB ValueObservation: feed updates automatically when pipeline writes new records
- Quiet "new photos available" indicator when updates arrive mid-session — no auto-scroll
- Keyset pagination: scrolling up loads older content
- Empty state: no photos yet

### Out of scope for this slice

- Stacking (all photos show as individual cards)
- Review interactions (keep/discard) — Slice 5
- Inbox — Slice 5
- Edit — Slice 6

---

### Technical Approach

**Feed query:** Single query joining `photos` and `devices`. `WHERE captured_at < :cursor ORDER BY captured_at DESC LIMIT 50`. Cursor is the `captured_at` of the oldest loaded photo. Initial query has no cursor.

**Section derivation (activity-based):** For each day, sort photos by `captured_at`. Find natural gaps in the shooting sequence where the interval between consecutive photos exceeds a threshold (suggested: 90 minutes as initial gap threshold). Each gap boundary starts a new section. Map sections to labels using clock as guardrail:
- Before 06:00 → "Early morning"
- 06:00–11:59 → "Morning"
- 12:00–16:59 → "Afternoon"
- 17:00–20:59 → "Evening"
- 21:00+ → "Night"
- Post-midnight (00:00–03:59) → attach to preceding day's evening/night section

**Thumbnail loading:** Use `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways`. Load on background queue. Cache in memory with `NSCache`. Display placeholder while loading.

**GRDB observation:** `ValueObservation.tracking { db in try Photo.fetchAll(db) }`. On new records, display "new photos available" banner. Do not auto-scroll. Tap to jump to latest.

---

### Acceptance Criteria

**AC-2.1 — Feed renders**
The app displays a scrollable feed of photos after ingest. No crash.

**AC-2.2 — Day grouping**
Photos are grouped by day with correct date headers. A shoot spanning two calendar days produces two day groups.

**AC-2.3 — Time-of-day sections**
Within a day with enough photos (5+), time-of-day section headers appear. Labels are human-readable ('Morning', 'Afternoon', 'Evening' etc.). Days with fewer than 5 photos show no section headers.

**AC-2.4 — Post-midnight rollback**
Photos taken between midnight and approximately 03:59 appear in the preceding day's feed, not as a new day. Verify with a test set containing post-midnight captures.

**AC-2.5 — Captured-at ordering**
Within each day and section, photos appear in ascending `captured_at` order (oldest first within section, sections in chronological order, days in reverse chronological order with most recent day at top).

**AC-2.6 — Thumbnail loading**
Thumbnails load without blocking scroll. Scrolling through 100+ photos does not stutter. Placeholder shown during load.

**AC-2.7 — Device tag**
Each photo card shows a device tag identifying the camera/phone it came from.

**AC-2.8 — Unseen indicator**
Each photo card shows the unseen visual indicator (since all photos start as `review_status = unseen`). The indicator is subtle — not a badge count, not alarming.

**AC-2.9 — Keyset pagination**
Loading older content works. Scroll up past the initial 2-day load and older days appear. No duplicate photos appear at page boundaries.

**AC-2.10 — Live update**
Simulate mid-session ingest by inserting a record directly into the database while the feed is open. The "new photos available" indicator appears. Tapping it scrolls to the latest. The feed does not auto-scroll without the tap.

**AC-2.11 — Empty state**
With no photos in the database, the feed shows a clean empty state (not a crash or blank screen).

**AC-2.12 — Performance**
With 500 photos, initial feed load completes in under 1 second. Scrolling is smooth.

---

### Edge Cases to Handle

- Photos with identical `captured_at` (burst mode, same second) — stable ordering (by hash or file_path as tiebreaker)
- Day with a single photo — no section headers, just day header and the photo
- Photos from multiple devices on the same day — interleaved by `captured_at` correctly
- Very long shooting day (16+ hours) — sections correctly segment by activity gaps, not just clock

---

## Slice 3 — Stacking

**Goal:** Similar photos collapse into stacks.

**One-line test:** A 200-photo burst session produces approximately 15 stacks in the feed.

---

### Scope

- Pipeline Stage 3 (Analysis): Vision.framework `VNGenerateImageFeaturePrintRequest` per photo, perceptual hash, write to `feature_vectors` table
- Pipeline Stage 4 (Stacking): time-window query, perceptual hash pre-filter, cosine similarity, connected-components grouping, write stack assignments to `stacks` and update `photos.stack_id`
- `feed_sections` pre-computation at ingest completion for each day
- Feed updated to render stacks as collapsed cards (best photo = highest sharpness in stack, simple Laplacian variance — this is a placeholder until Slice 4's full culling model)
- Stack card shows photo count badge
- "See all" control on stack card to expand and view all photos in the stack
- Recomputation path: changing threshold reruns grouping using stored vectors (no re-analysis)
- Background processing: analysis and stacking run at low priority

### Out of scope for this slice

- The full two-stage culling model — Slice 4
- User stack management (manual add/remove) — Slice 5

---

### Technical Approach

**Analysis (Stage 3):** `VNGenerateImageFeaturePrintRequest` produces a 2048-float feature vector. Run with `.background` QoS. Process photos that have `vector_valid = false` (i.e. all newly ingested photos). Write vector as raw `Data` (float32 little-endian) to `feature_vectors.feature_vector`. Compute perceptual hash as 8-byte dHash (difference hash on 9x8 greyscale downscale of thumbnail).

**Stacking (Stage 4):** For each newly analysed photo, query all photos within the time window (default 2 minutes, configurable) where `vector_valid = true`. Pre-filter candidates: perceptual hash Hamming distance < 10. For candidates passing pre-filter, compute cosine similarity against feature vectors. Apply connected-components grouping at threshold (default ~0.90). Write results: create/update `stacks` records, set `photos.stack_id`.

**Cosine similarity:** Computed in Swift using Accelerate framework (`vDSP_dotpr` for dot product, `vDSP_svesq` + `sqrt` for norms). Do not use any external library.

**Connected components:** Simple union-find. If photo A has similarity > threshold with photo B, and photo B has similarity > threshold with photo C, then A, B, C are in the same stack even if A-C similarity is below threshold.

**Placeholder best photo:** Until Slice 4, elect best photo as the one with highest Laplacian variance (sharpness proxy) computed on a small thumbnail. Store as `best_photo_id` in stacks table with `best_photo_source = auto_culling`.

**feed_sections pre-computation:** After stacking completes for a day's photos, compute section boundaries and write to `feed_sections` table. Recompute for a day if new photos arrive for it.

---

### Acceptance Criteria

**AC-3.1 — Analysis runs**
After ingest, all photos have entries in `feature_vectors` with `vector_valid = true`. Verify in database.

**AC-3.2 — Stacks form**
A 200-photo burst from a single session collapses to 8–25 stacks (target ~15). The exact number varies by shooting diversity; the range is the acceptance band.

**AC-3.3 — Time window respected**
Photos taken more than 2 minutes apart are never stacked together. Verify by examining stacks — each stack's photos should all have `captured_at` within a 2-minute window.

**AC-3.4 — Connected-components**
Three photos where A~B and B~C (both above threshold) but A and C are not directly above threshold: all three form one stack. Verify with a constructed test case.

**AC-3.5 — Feed shows stacks**
The feed renders stack cards (not individual photo cards) for stacked photos. Each stack card shows the best photo and a count badge.

**AC-3.6 — See all**
Tapping the "see all" control on a stack card reveals all photos in the stack. All photos in the stack are accessible.

**AC-3.7 — Individual photos remain**
Photos not stacked (unique or low similarity to neighbours) still appear as individual cards in the feed.

**AC-3.8 — Re-insertion deduplication**
Re-inserting the same SD card: zero new stacks created, zero new feature vectors computed, zero duplicate records. Existing stacks unchanged.

**AC-3.9 — Recomputation**
Changing the stacking threshold (simulated by updating the constant) and triggering recomputation: stacks reform correctly using stored feature vectors. No re-analysis runs (verify by checking that no new `VNGenerateImageFeaturePrintRequest` calls are made).

**AC-3.10 — Performance**
Analysis of 200 photos completes in under 5 minutes on Apple Silicon. Stacking assignment completes in under 10 seconds for 200 photos.

**AC-3.11 — Background operation**
Analysis and stacking do not block the UI. The feed remains scrollable and responsive during background processing.

**AC-3.12 — feed_sections computed**
After stacking completes for a day, `feed_sections` records exist for that day. Days with 5+ stacks have section records. Days with fewer than 5 stacks have no section records.

---

### Edge Cases to Handle

- Single photo on a day — no stacking, individual card, no sections
- Photos from two devices taken simultaneously (same timestamp) — may or may not stack based on visual similarity
- Very long burst (50+ near-identical frames) — all collapse to a single stack
- Mixed session: some in burst, some isolated — correctly separates into stacks and individual cards
- Photo with unreadable image data (corrupted) — skip Vision analysis, mark `vector_valid = false`, continue

---

## Slice 4 — Best Photo Selection

**Goal:** The right photo is on top of each stack.

**One-line test:** For portrait and group stacks, the sharpest frame with open eyes surfaces reliably.

---

### Scope

- Pipeline Stage 5 (Culling): full two-stage best image selection model
- Stage 1: saliency + face detection across all frames in the stack, subject region establishment, pattern recognition
- Stage 2: per-frame scoring against subject region — Layer 1 (error elimination), Layer 2 (ranking), Layer 3 scaffolding (weights neutral, no-op in V1)
- `best_photo_source` protection: `user_selected` is never overwritten
- Individual non-stacked photos receive quality scores (for future sorting/filtering use)
- All Vision analysis applied to subject crop region, not full frame

### Out of scope for this slice

- Layer 3 learning activation — that is post-V1
- VLM-based best photo enhancement — post-V1
- Motion blur and tilted horizon signals — deferred per PRD Section 7.9

---

### Technical Approach

**Stage 1 — Subject identification:**
For each photo in the stack, run `VNGenerateAttentionBasedSaliencyImageRequest`. Extract the salient region bounding box. If faces present (`VNDetectFaceRectanglesRequest`), use the face bounding box union as the subject anchor instead of saliency centroid. Average subject region centroids across all frames to establish the stack's intended subject region.

**Pattern recognition:**
- Compute variance of subject centroid positions across frames. Low variance = consistent framing (intentional). High variance = framing inconsistency.
- Compute variance of subject region area across frames. Low variance = consistent zoom/crop intent.
- Compute per-frame sharpness (Laplacian variance on subject crop). High cross-frame variance with no systematic pattern = focus errors.
- Compute per-frame exposure (mean luminance on subject crop). Systematic exposure variation = possible bracketing intent; flag but do not penalise.

**Stage 2 — Per-frame scoring:**

Layer 1 (eliminates frames — high confidence):
- Subject sharpness below threshold (Laplacian variance on subject region < configurable floor)
- Subject severely over/underexposed (mean luminance on subject region < 20 or > 235 on 0–255 scale)
- Eyes closed when face is subject (`VNDetectFaceLandmarksRequest` — measure eye aspect ratio)

Layer 2 (ranks surviving frames):
- Subject sharpness score (normalised Laplacian variance)
- Subject exposure quality (distance from ideal luminance, 118 target)
- Eye openness score across all detected faces (mean eye aspect ratio)
- Subject position consistency (distance from stack centroid position)

Weighted sum with neutral starting weights (Layer 3 placeholder). Elect the highest-scoring frame as `best_photo_id`. Set `best_photo_source = auto_culling`.

---

### Acceptance Criteria

**AC-4.1 — Portrait stack: open eyes**
For a stack of portrait frames where some have closed eyes and some have open eyes, the elected best photo has open eyes in all detected faces (or the most open eyes if no perfect frame exists).

**AC-4.2 — Portrait stack: sharpness**
For a stack where frames vary in sharpness, the elected best photo is visibly sharper at the subject (face) region than the alternatives. Verify by inspection.

**AC-4.3 — Group shot: aggregate eye openness**
For a group shot stack, the elected best photo is the frame where the most people have open eyes. Verify by inspection.

**AC-4.4 — Layer 1 elimination**
Create a test set with one severely overexposed frame, one out-of-focus frame, and several acceptable frames. The overexposed and out-of-focus frames are not elected as best photo.

**AC-4.5 — Landscape: sharpness and exposure**
For a landscape stack (no faces), the elected best photo is the sharpest and best-exposed frame. Verify by inspection.

**AC-4.6 — user_selected protection**
Manually set `best_photo_source = user_selected` on a record (simulated, or via Slice 5 interaction). Re-run culling pipeline. The `best_photo_id` and `best_photo_source` for that stack are unchanged.

**AC-4.7 — Subject region, not full frame**
For a portrait where the background is intentionally soft (shallow DoF), the model does not penalise the frame for background softness. Verify by constructing a test case and checking that background-soft frames are not eliminated by Layer 1 sharpness check.

**AC-4.8 — Non-stacked photo scoring**
Individual photos (not in stacks) receive quality scores. `feature_vectors` or a quality column is updated. No crash on individual photo processing.

**AC-4.9 — Layer 3 placeholder**
The code structure for Layer 3 taste weight application exists and compiles. Weights are all neutral (1.0 or equal). The system functions identically to Layer 2 only. No actual taste signal processing occurs.

---

### Edge Cases to Handle

- Stack with all frames having closed eyes — elect sharpest/best-exposed; do not crash
- Stack with no detectable faces (saliency only) — fall back gracefully to saliency-based subject region
- Stack where all frames fail Layer 1 — elect the least-bad frame (lowest Layer 1 penalty score), log warning
- Stack of one photo — trivially elect that photo; skip multi-frame analysis
- Face detection returning zero faces despite visible face (detection miss) — fall back to saliency

---

## Slice 5 — Review Interactions

**Goal:** Run a complete cull session from start to finish.

**One-line test:** Open the app, work through the inbox, keep/discard photos, override stack selections, and close with all changes persisted.

---

### Scope

- Keep / discard action on individual photos and stacks (marks best photo)
- `photos.review_status` updated in database on action
- Visual treatment update in feed (immediate, optimistic)
- Manual best photo promotion within a stack
- Manual stack management: add photo to stack, remove photo from stack, restack (move photo to different stack)
- `stack_edits` table: all manual operations recorded
- `taste_signals` table: all user actions recorded (signal capture only — not acted on in V1)
- Inbox button: count of days with at least one unseen photo
- Inbox count query: `SELECT COUNT(DISTINCT DATE(captured_at)) FROM photos WHERE review_status = 'unseen'`
- Inbox view: focused view, only days with unseen content, stacks collapsed to best photo
- Inbox count real-time update via GRDB observation
- Inbox dismissal: tap outside or close button

### Out of scope for this slice

- Learning layer activation — post-V1
- Undo/redo — not in V1 scope (manual stack edits can be reversed by the user manually)

---

### Technical Approach

**Keep/discard:** Update `photos.review_status` in a GRDB write transaction. For a stack card, marking 'kept' marks the `best_photo_id` photo as kept. Marking 'discarded' marks it as discarded. Both update `review_status` on the specific photo. Taste signal written: `signal_type = kept` or `discarded`.

**Visual treatment:** Use GRDB ValueObservation on `review_status`. Feed items update visual treatment (desaturated, opacity reduced, etc. for discarded) immediately. Optimistic update on main thread before DB write confirms.

**Manual best photo promotion:** User taps a non-best photo in the expanded stack view and selects "use as best". Updates `stacks.best_photo_id` and sets `stacks.best_photo_source = user_selected`. Records in `stack_edits` (action = 'promoted') and `taste_signals` (signal_type = 'best_photo_changed').

**Stack add/remove:** Drag-and-drop or contextual menu. Updates `photos.stack_id`. Records in `stack_edits`. Records in `taste_signals` (signal_type = 'stack_modified').

**Inbox query:** GRDB ValueObservation on `SELECT COUNT(DISTINCT DATE(captured_at)) FROM photos WHERE review_status = 'unseen'`. Button label updates live.

---

### Acceptance Criteria

**AC-5.1 — Keep action**
Marking a photo as 'kept' updates `review_status = kept` in database. The photo's visual treatment changes in the feed. Persists after app restart.

**AC-5.2 — Discard action**
Marking a photo as 'discarded' updates `review_status = discarded` in database. Visual treatment updates. Persists after app restart.

**AC-5.3 — Unseen indicator clears**
After marking a photo kept or discarded, the unseen visual indicator is removed. If all photos in a day are reviewed, the day no longer counts in the inbox.

**AC-5.4 — Manual best photo promotion**
Promoting a non-best photo to best: `best_photo_id` updates in database, `best_photo_source = user_selected`, feed updates to show new best photo on stack card. Persists after restart.

**AC-5.5 — user_selected survives pipeline rerun**
After manual promotion, trigger the culling pipeline to reprocess the stack. `best_photo_id` and `best_photo_source = user_selected` are unchanged. The pipeline's elected photo is not applied.

**AC-5.6 — Stack edit recorded**
Every manual add/remove/restack action has a corresponding record in `stack_edits`. Verify by querying the table after performing each action type.

**AC-5.7 — Taste signals recorded**
Every user action (keep, discard, best photo change, stack modification) has a corresponding record in `taste_signals`. Verify by querying the table.

**AC-5.8 — Inbox count correct**
Inbox button shows the correct count of days with at least one unseen photo. Verify against manual count from database.

**AC-5.9 — Inbox count live update**
After marking all photos in a day as reviewed, the inbox count decrements in real time without requiring an app restart or manual refresh.

**AC-5.10 — Inbox view**
Opening the inbox shows only days with unseen content, stacks collapsed to best photo. Reviewed days do not appear.

**AC-5.11 — Inbox view updates**
While the inbox is open, reviewing a day removes it from the inbox view in real time.

**AC-5.12 — Visual treatment persistence**
After restart, kept photos still show 'kept' visual treatment. Discarded photos still show 'discarded' treatment. Unseen photos still show unseen indicator.

---

### Edge Cases to Handle

- Discarding the current best photo in a stack — promote the next-best automatically, or demote to individual if stack becomes empty
- Removing the last photo from a stack — stack record should be deleted, photo becomes individual
- Marking 'kept' on an already-kept photo — no-op (or toggle to unseen, design decision: choose no-op for V1)
- Empty inbox (no unseen days) — button shows zero, tapping shows empty state gracefully

---

## Slice 6 — Edit Layer

**Goal:** Non-destructive editing from Theme through Adjustments through Geometry.

**One-line test:** Select a Theme, tweak a slider, deselect the Theme, and the pre-Theme state is exactly restored. Original file is unchanged throughout.

---

### Scope

- Core Image rendering pipeline (applies edits at screen resolution for preview, full resolution for export)
- 4–5 hand-crafted Theme presets (Moody, Warm, Clean, Cinematic, + 1 optional)
- Adjustments panel: 6 sliders (warmth, contrast, fade, grain, vignette, saturation)
- Theme/Adjustments interaction: Theme populates Adjustments, parks pre-Theme state
- Deselect Theme: restores pre-Theme snapshot; in-Theme tweaks discarded
- Switch Theme: replaces Theme values; pre-Theme snapshot preserved
- `adjustment_source` field tracking
- Geometry: auto-straighten via `VNDetectHorizonRequest`, manual rotation dial
- Geometry persists across Theme changes (not part of snapshot/restore cycle)
- Prompts: input field visible with clear "requires enhanced model" gate, non-functional in V1
- `edits` table: full edit state stored as JSON per photo
- Only one active edit chain per photo at a time (`is_active = true`)
- Original file hash before and after: must be identical

### Out of scope for this slice

- VLM/Prompts activation — post-V1
- Cropping — post-V1 per PRD Section 7.8
- Edit history / undo beyond Theme snapshot — not in V1 scope
- Export at full resolution — Slice 7

---

### Technical Approach

**Core Image pipeline:** Chain of `CIFilter` instances applied in sequence. Filter chain defined by current edit parameters. Render to `NSImage` for display. Parameters map to filters:
- warmth → `CITemperatureAndTint`
- contrast → `CIColorControls` (contrast)
- fade → `CIColorControls` (brightness lift) or `CIExposureAdjust`
- grain → `CIRandomGenerator` + blend
- vignette → `CIVignette`
- saturation → `CIColorControls` (saturation)
- straighten_angle → `CIStraightenFilter` or `CIAffineTransform`

**Edit state JSON:** Full snapshot of current parameters stored on every change (debounced, not on every slider tick). `is_active` ensures only one chain per photo.

**Theme snapshot:** On Theme selection, read current `parameters_json` (or zeros if no edits), store as `pre_theme_adjustments` key within the JSON. On deselect, restore from `pre_theme_adjustments`. On Theme switch, replace adjustment values but preserve `pre_theme_adjustments`.

**Auto-straighten:** Run `VNDetectHorizonRequest` on the photo. Extract `angle` from result. Offer as suggested value with one-tap apply. User can adjust with the rotation dial.

**Original file integrity:** Never touch `file_path`. All writes go to the `edits` table only.

---

### Acceptance Criteria

**AC-6.1 — Theme applies**
Selecting a Theme populates the Adjustments panel with that Theme's values. The preview updates immediately.

**AC-6.2 — Theme snapshot**
After making manual slider adjustments, selecting a Theme: the pre-Theme slider values are stored. Deselecting the Theme: the pre-Theme values are exactly restored. Verify slider values match before-Theme state precisely.

**AC-6.3 — In-Theme tweaks discarded on deselect**
With a Theme active, move a slider. Deselect the Theme. Verify the slider returns to its pre-Theme value, not the in-Theme tweaked value.

**AC-6.4 — Theme switch preserves snapshot**
Select Theme A, make a slider tweak. Switch to Theme B. Verify Theme B's values load. Deselect Theme B. Verify the pre-Theme A state (from before Theme A was selected) is restored — not Theme A's values.

**AC-6.5 — Adjustments render correctly**
Each of the 6 adjustment parameters visibly affects the preview in the expected direction. Warmth shift makes image warmer. Fade lifts shadows. Vignette darkens edges. Etc.

**AC-6.6 — Geometry independent**
Set a straighten angle. Select a Theme. Verify straighten angle is unchanged. Deselect Theme. Verify straighten angle is still unchanged. Geometry is completely independent of the Theme snapshot/restore cycle.

**AC-6.7 — Auto-straighten**
Tapping auto-straighten on a photo with a clearly non-horizontal horizon produces a suggested correction angle close to the actual horizon deviation (within ±1°). User can apply or ignore.

**AC-6.8 — Edit persists**
Edit state (Theme, slider values, geometry) persists after app restart. Loading the same photo shows the same edit state.

**AC-6.9 — Original file unchanged**
Compute SHA-256 of the original file before editing. After applying Theme, sliders, and geometry, compute SHA-256 again. Hashes must be identical.

**AC-6.10 — Prompts gate**
The Prompts input field is visible in the edit UI. Tapping it or attempting to use it shows a clear explanation that it requires an enhanced model download. No crash.

**AC-6.11 — adjustment_source tracked**
After each of these scenarios, `adjustment_source` in the JSON has the correct value: auto_suggested (pipeline suggestion), theme_default (Theme selected, no manual tweaks), theme_modified (Theme with slider tweaks), user_manual (manual sliders, no Theme).

---

### Edge Cases to Handle

- Photo with no edit history: Adjustments panel shows zeros, no Theme selected
- Switching between photos rapidly: edit state loads correctly for each without bleed-through from previous photo
- Very bright or very dark photo: Core Image rendering handles extreme source values without clipping crashes
- Auto-straighten on a photo with no detectable horizon: suggests 0° (no change), handles gracefully

---

## Slice 7 — Share and Export

**Goal:** The complete workflow from ingest to share.

**One-line test:** Select a photo with edits applied, share it, and the recipient receives a correctly processed image. Export a folder of 10 photos — all edits applied, all at full resolution.

---

### Scope

- Quick share: native macOS share sheet, processed image (edits applied at screen-appropriate resolution for share)
- Publish mode: multi-photo selection UI, optional title and description fields, export to user-chosen folder
- Export: applies all active edits at full resolution via Core Image pipeline
- Export: full-resolution RAW decoding (for Fuji RAF: use `CIRAWFilter` or `CGImageSourceCreateImageAtIndex` with full resolution option)
- Export format: JPEG at 95% quality, or TIFF — user choice
- No network calls in any share or export path
- Works fully offline

### Out of scope for this slice

- Caption/description suggestions — post-V1 (VLM-gated per PRD Section 7.7)
- Direct platform API integrations — explicitly out of V1 scope

---

### Acceptance Criteria

**AC-7.1 — Quick share**
Tapping quick share on a photo opens the native macOS share sheet with the processed image. The image shared has all active edits applied visibly (Theme, sliders, geometry). Recipient can open it as a normal image file.

**AC-7.2 — Quick share unedited**
Tapping quick share on a photo with no edits shares the unmodified original (no colour shift or processing artefacts from an empty filter chain).

**AC-7.3 — Publish selection**
The publish UI allows selecting multiple photos. Selected photos are clearly indicated. Deselecting works.

**AC-7.4 — Export produces folder**
Exporting produces a folder at the user-chosen location. The folder contains one image file per selected photo. File names are reasonable (e.g. date + original filename).

**AC-7.5 — Export resolution**
Exported images are full resolution (matching the original file's pixel dimensions). Verify with `mdls` or Preview's image info.

**AC-7.6 — Edits applied at export**
Exported images have all active edits applied. Verify visually: Theme, slider adjustments, geometry (straightening) are all reflected in the export.

**AC-7.7 — No network call**
Export completes with no network activity. Verify with a network monitor (e.g. Little Snitch or macOS network profiler) that zero network calls are made during share or export.

**AC-7.8 — Original unchanged**
After export, the original file's SHA-256 is unchanged.

**AC-7.9 — Offline operation**
Turn off Wi-Fi and disconnect ethernet. Share and export still work completely.

---

## Slice 8 — Polish and Hardening

**Goal:** V1 is actually done and reliable.

**One-line test:** Use the app daily for a week and encounter no crashes, data loss, or pipeline failures.

---

### Scope

- Watched folder source: FSEvents-based monitoring, configurable folder path, auto-ingest on file arrival
- Photos library source: PHPhotoLibrary change observer, treated as one source among many
- Pipeline resumability: sleep/wake, app backgrounded at each of the 5 pipeline stages, force-quit mid-pipeline — all handled gracefully with correct resume on next launch
- Large library performance: 1000+ photos, keyset pagination verified, thumbnail cache efficiency
- Edge case hardening: corrupted files, unreadable EXIF, partial moves, disk full during ingest
- Settings screen: storage path configuration, stacking threshold, time window, ingest sources on/off
- Empty states: all views have correct empty states
- Error states: ingest failure, analysis failure, file not found — all surface appropriately without crash
- Memory: no runaway memory growth during Analysis stage (Vision.framework requests released promptly)

---

### Acceptance Criteria

**AC-8.1 — Watched folder**
Placing an image file into the watched folder triggers ingest within 5 seconds. File is processed through the full pipeline. Verified for RAF, HEIC, and JPEG.

**AC-8.2 — Photos library source**
Adding a photo to the macOS Photos library (with Photos library source enabled) triggers ingest within 30 seconds.

**AC-8.3 — Sleep/wake resume — Stage 2**
Ingest 100 photos. Force sleep mid-ingest (after ~30 photos). Wake. Verify remaining photos are ingested correctly. No duplicates. No missed files.

**AC-8.4 — Sleep/wake resume — Stage 3**
Same test for Analysis stage. Verify `vector_valid` correctly marks completed vs incomplete on wake.

**AC-8.5 — Sleep/wake resume — Stage 4/5**
Same test for Stacking and Culling stages.

**AC-8.6 — Large library performance**
With 1000 photos in the database: initial feed load under 2 seconds, scroll through 500 photos without perceptible lag, inbox count query under 100ms.

**AC-8.7 — Memory during analysis**
Analyse 200 photos consecutively. Memory usage does not grow unboundedly. Vision.framework request objects are released after each photo. Peak usage stays below 500MB.

**AC-8.8 — Corrupted file handling**
Place a truncated/corrupted image file on the SD card. Ingest does not crash. The corrupted file is skipped with a log entry. Other files in the batch are processed normally.

**AC-8.9 — Disk full during ingest**
Simulate disk full (small RAM disk). Ingest fails gracefully. No partial records left in database. App continues running. Error is surfaced to user.

**AC-8.10 — Settings persistence**
Storage path, stacking threshold, and time window settings persist across app restarts.

**AC-8.11 — All empty states**
Every view (feed, inbox, published set, settings) has a clean empty state. No crash or blank screen anywhere with zero data.

**AC-8.12 — No crashes in a week of daily use**
Subjective but important. Use the app daily through real shooting sessions. Zero unexpected crashes. Zero silent data loss events.

---

## Slice Dependency Map

```
Slice 1 (Foundation)
    └── Slice 2 (Feed)
            └── Slice 3 (Stacking)
                    └── Slice 4 (Best Photo Selection)
                            └── Slice 5 (Review Interactions)
                                    └── Slice 6 (Edit Layer)
                                            └── Slice 7 (Share/Export)
                                                        └── Slice 8 (Polish)
```

Each slice requires all preceding slices to be complete and committed before starting.
