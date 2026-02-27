# Framed — Product Requirements Document

**Version:** 1.0  
**Status:** Final for V1  
**Last Updated:** February 2026  
**Type:** Living document — updated only as new decisions are formally made

---

## 1. Product Overview

Framed is a photography workflow app for photographers who want a fast, personal, private way to ingest, review, cull, and lightly edit their photos. It is built for the creator's own daily use first, with platformisation considered only after it proves genuinely useful in practice.

---

## 1.1 Core Principles

**Privacy first.** Everything runs locally on device. No cloud dependency except optional user-controlled iCloud sync via CloudKit. No network required. Original RAW files are never touched — Framed is fully non-destructive.

**Personalised.** Framed learns the user's taste over time — which photos they keep, which edits they accept, what style they gravitate toward — and gets progressively better at culling and editing the more it is used. The learning layer runs entirely on-device.

**Anti-overwhelm by design.** The core UX paradigm is a continuous reverse chronological feed (latest first) grouped by day and time of day. Photos appear in the order they were taken, across all devices, interleaved naturally. Framed never reorders, promotes, or makes recommendations about what to look at. Similar photos taken in quick succession are collapsed into stacks purely to reduce visual noise — the order and context of your shoot is always preserved.

**Source agnostic.** Framed handles photos from any camera or device. Device is metadata, not structure. Designed for Fuji RAW (RAF format) in V1 but architected to handle any source from the start.

**Built for self first.** V1 is built for the creator's own use. Platformisation comes only after it proves useful in daily personal use.

---

## 1.2 Target Platform

Apple ecosystem only. macOS for V1. iOS and iPadOS are the next targets after V1 proves useful in daily personal use. Single Swift codebase using SwiftUI across all three platforms — UI work done for Mac is not wasted when iOS and iPadOS are added.

Photos can come from any source regardless of platform — source agnosticism refers to photo origin, not app platform.

---

## 1.3 Core Concepts

**Stack** — A group of visually similar photos taken in quick succession, collapsed into a single card in the review feed. The best image surfaces on top. The rest are accessible via a 'see all' control. Similarity is determined by a configurable threshold (default ~90%) within a configurable time window (default ~2 minutes).

**Day** — The top-level grouping in the feed. All photos from all devices on a given day appear together, interleaved in the order they were taken.

**Time of Day Label** — A loose, human-readable label within a day ('This morning', 'This evening', 'Yesterday afternoon') that acts as a gentle visual separator in the scroll. Not a hard navigation layer.

**Device Tag** — A small icon or label on each stack indicating which device or camera it came from (Fuji, iPhone, etc.). Informational only, not structural.

---

## 2. Functional Requirements

### 2.1 Ingest

Detect new photos from any source. Files are moved (not copied) to the Framed-managed storage location on trigger. SD card plug-in is the primary V1 trigger. Ingest runs in the background without any action required after the initial trigger.

**Ingestion sources:**
- SD card mount — primary V1 trigger, detected via DiskArbitration framework on Mac
- Watched folder — user-configurable folder monitored via FSEvents
- Photos library — via PHPhotoLibrary change observer, treated as one source among many
- AirDrop / local transfer — future consideration only

The user configures the destination path, defaulting to `~/Pictures/Framed/`. Original files are never modified after move.

Deduplication is handled by SHA-256 content hash. If a file with the same hash already exists in the database, the ingest attempt is skipped silently. This makes SD card re-insertion safe.

---

### 2.2 Review Feed

A continuous scroll feed grouped by day, then by time of day label. Stacks and individual photos appear in the order they were taken across all devices. The feed always opens at the most recent unseen item. Unseen stacks have a subtle visual indicator within the feed — understated enough not to create pressure, visible enough to orient the user at a glance.

The feed shows all photos regardless of review status. There is no separate reviewed/unreviewed split in the main feed — review state is communicated through visual treatment only.

---

### 2.3 Inbox

A persistent inbox button in the top-right of the feed shows the count of days with at least one unseen photo. The count reflects days, not individual photos or stacks — '3 days to review' is immediately legible.

Tapping the inbox opens a focused view showing only days with unseen content, stacks collapsed to their best photo, in reverse chronological order. The inbox is opt-in — it can be ignored entirely without consequence to the main feed.

The inbox count updates automatically as new photos are ingested and as the user marks items reviewed.

---

### 2.4 Culling

Automatically analyse each import, group similar photos into stacks, and surface the best image within each stack. Culling happens in the background before the user opens the app. Goal: reduce a session of 200 photos to approximately 15 stacks or individual cards for review. Culling never makes a keep/discard decision — it only surfaces the best candidate within each stack.

#### Best Image Selection Model

Selection follows a subject-first, two-stage model. The stack is assessed as a whole before individual frames are scored. Consistency across frames signals intent; inconsistency signals error. The system never pretends to have certainty it doesn't have — the user's override is always the loudest signal.

**Stage 1 — Subject Identification and Pattern Recognition (stack-level)**

Before scoring individual frames, the stack is analysed as a whole to understand what the subject is and what the photographer's consistent intent looks like across frames. This uses Vision.framework saliency detection and face detection across all frames.

- Vision attention saliency identifies the region drawing the eye most strongly
- If faces are present, face detection takes precedence as the subject anchor
- Saliency centroid is computed per frame and averaged across the stack to establish the intended subject region
- Consistent subject position = intentional framing; treat as reference
- Consistent subject crop (head always at shoulder) = intentional framing, not error
- Sharpness varying randomly = focus errors, prefer sharpest
- Sharpness varying systematically (subject soft, background sharp) = possible depth of field intent, defer to taste signals
- Exposure varying randomly = accidental variation, prefer best exposed
- Exposure varying systematically = possible bracketing intent, note but do not penalise
- Tricky signals (motion blur, tilted horizon) are deferred from V1

**Stage 2 — Per-Frame Scoring (relative to subject)**

Each frame is scored against the subject region established in Stage 1. All Vision.framework analysis is applied to the subject crop, not the full frame.

- **Layer 1 — Eliminate clear errors (high confidence).** Subject sharpness below threshold; subject severely over/underexposed; eyes closed when face is subject. Frames that fail are deprioritised before Layer 2 runs.
- **Layer 2 — Surface the best moment (moderate confidence).** Among frames passing Layer 1: subject sharpness score, subject exposure quality, eye openness score, subject position consistency with stack pattern.
- **Layer 3 — Apply learned taste (personalised, grows over time).** Weights for Layer 2 shift based on accumulated taste_signals. Weights start neutral and drift gradually. Never overrides Layer 1 error elimination.

---

### 2.5 Stack Management

The user can manually add or remove images from a stack, or restack entirely. Manual stack edits are recorded as operational events (stack_edits table) and as taste signals (taste_signals table). User intent always takes precedence — manually promoted best photos are never overwritten by automatic culling.

Stacking is scoped to photos taken within the same time window. Cross-session grouping is post-V1.

---

### 2.6 Edit

All edits are non-destructive. The original file is never modified. Edits are stored as parameters in the edits table and applied at render and export time via Core Image. The edit layer has four components: Theme, Adjustments, Geometry, and Prompts.

#### Theme

A small set of named vibe presets (4–5 in V1, e.g. Moody, Warm, Clean, Cinematic). Each Theme is a hand-crafted bundle of Adjustment parameter values. Themes are presented separately from Adjustments in the UI.

- **Selecting a Theme:** Adjustments panel clears and repopulates with Theme values. Pre-Theme adjustment state is snapshotted and parked.
- **Deselecting a Theme:** Pre-Theme snapshot is restored. Any tweaks made while Theme was active are discarded.
- **Switching Themes:** Replaces current Theme's values. Pre-Theme snapshot is preserved until fully deselected.

#### Adjustments

Tonal and colour parameters applied via Core Image filters. When no Theme is active, panel shows auto-suggested values from the pipeline or zeros.

V1 adjustment parameters: warmth, contrast, fade (lifts blacks), grain, vignette, saturation.

The `adjustment_source` field tracks how values were set: `auto_suggested`, `theme_default`, `theme_modified`, or `user_manual`.

#### Geometry

Straightening only in V1. Stored as a rotation angle applied at render time. A one-tap auto-straighten option uses Vision.framework horizon detection. Geometry is independent of Theme and Adjustments — it persists across Theme changes and is not affected by the snapshot/restore cycle.

#### Prompts (VLM-gated)

Natural language edit instructions (e.g. "make this feel like golden hour"). Requires an on-device VLM to be downloaded. The VLM acts as a prompt-to-parameters translator only — it does not manipulate pixels directly. The prompt input field is visible in the UI but shows a clear "requires enhanced model" explanation when no VLM is present.

#### Edit State Storage

Full edit state stored as JSON in the edits table. Example:

```json
{
  "theme": "moody",
  "adjustments": {
    "warmth": -0.2,
    "contrast": 0.35,
    "fade": 0.15,
    "grain": 0.2,
    "vignette": 0.25,
    "saturation": -0.1
  },
  "adjustment_source": "theme_modified",
  "pre_theme_adjustments": {
    "warmth": 0.1,
    "contrast": 0.05,
    "adjustment_source": "auto_suggested"
  },
  "geometry": { "straighten_angle": 1.5 },
  "prompt": null
}
```

---

### 2.7 Share

Two modes:

- **Quick share** — single photo or stack via the native macOS share sheet. No Framed involvement beyond handing off the processed file.
- **Publish mode** — select a curated set of photos, add optional title and description, export as a folder of processed images ready for upload. Export applies all active edits non-destructively at full resolution. No direct platform API integrations in V1 — export and upload is the user's action.

---

## 3. Technical Architecture

Framed's architecture is local-first throughout. SQLite is the single source of truth — all pipeline stages read from and write to the database, making every stage resumable if the app is backgrounded or the machine sleeps mid-run.

---

### 3.1 Technology Stack

| Layer | Choice |
|---|---|
| UI Framework | SwiftUI — Mac first, iOS/iPadOS later. Single codebase. |
| Language | Swift with structured concurrency (async/await, task groups) |
| Database | SQLite via GRDB — embedded, local, same schema across all Apple platforms |
| ML / Vision | Vision.framework (featurePrint, quality analysis) + Core ML for custom models |
| Sync (opt-in) | CloudKit — user's own iCloud account. Post-V1. |
| SD Card Detection | DiskArbitration framework (Mac) |
| Folder Watching | FSEvents (Mac) |
| Photos Library | PHPhotoLibrary with change observer |

---

### 3.2 Processing Pipeline

Five discrete, resumable stages. Each reads from and writes to the database. If the app is backgrounded or the machine sleeps mid-pipeline, every stage resumes from where it left off on next launch.

**Stage 1 — Detection.** Watches for ingestion triggers. Each trigger emits a list of file paths or asset identifiers into a job queue. No files are copied or analysed at this stage.

**Stage 2 — Ingest.** For each queued file: compute SHA-256 hash, check for existing record (deduplication), move file to Framed-managed storage, write photos record with `review_status = unseen`. Sequential, not concurrent, to avoid file system races.

**Stage 3 — Analysis.** For each ingested photo without a feature vector: run Vision.framework featurePrint (2048-dimension float vector), compute perceptual hash (8 bytes), write to feature_vectors table, mark `vector_valid = true`. Runs at lowest priority on Neural Engine. Approximately 50–150 photos/minute on Apple Silicon.

**Stage 4 — Stacking.** For each newly analysed photo: query photos within the time window (default 2 min), compare perceptual hashes as cheap pre-filter, then cosine similarity on feature vectors for candidates above threshold, run connected-components grouping, write stack assignments and similarity scores. Records `formation_method = auto` and threshold used.

**Stage 5 — Culling.** For each stack: run the two-stage best image selection model. Elects best photo and updates `best_photo_id`. Records `best_photo_source = auto_culling`. Never overwrites `best_photo_source = user_selected`. Individual non-stacked photos also receive quality scores.

---

### 3.3 Stacking Model

- At ingest: compute similarity, form stacks, store both the stack assignment and the raw feature vector
- The feature vector is the reusable input — recomputation re-runs grouping logic over stored vectors without re-running Vision analysis
- Sliding window comparison: only photos within the time window are compared
- Grouping uses connected-components logic: if A~B and B~C, all three form one stack even if A and C are not directly above threshold
- `stack_edits` table records all manual add/remove/restack actions as both operational events and taste signals

---

### 3.4 Feed Architecture

#### Data Model

```swift
struct FeedDay { let date: Date; let label: String; let sections: [FeedSection] }
struct FeedSection { let timeOfDayLabel: String; let items: [FeedItem] }
enum FeedItem { case stack(Stack, bestPhoto: Photo); case photo(Photo) }
```

Time-of-day labels are derived from `captured_at` in the Swift layer, not stored in the database. Bucketing is activity-based — sections are derived from natural gaps in shooting frequency for each day, with fixed clock times as a soft guardrail. Post-midnight photos attach to the preceding day's evening session.

#### Query Strategy

Keyset pagination rather than OFFSET. Initial load fetches the most recent two days. As the user scrolls up, older content is appended using `WHERE captured_at < last_seen_timestamp LIMIT N`. GRDB ValueObservation observes the photos table for live updates.

#### Live Updates

When new photos are ingested while the user is in the feed, a quiet indicator appears at the top ('New photos available') which the user can tap to jump to the latest. No auto-scroll.

#### Inbox Query

```sql
SELECT COUNT(DISTINCT DATE(captured_at)) FROM photos WHERE review_status = 'unseen'
```

---

### 3.5 Storage Model

Framed manages one canonical copy of each file. Files are moved (not copied) from source to the Framed storage directory on ingest. SHA-256 deduplication prevents re-ingestion.

Storage sizing: feature vectors (~8KB/photo) are negligible compared to RAW files (~25–50MB/photo for Fuji RAF). No storage optimisation needed for vector cache — store permanently.

---

### 3.6 Sync

CloudKit is the intended opt-in sync layer (post-V1). Data lives in the user's own iCloud account. The local-first architecture is not dependent on sync — sync is a layer added on top.

---

## 4. Database Schema

SQLite via GRDB. Schema is identical across Mac, iOS, and iPadOS.

### 4.1 photos

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | SHA-256 content hash — canonical identifier |
| file_path | TEXT NOT NULL | Path to original file in Framed storage — never modified |
| source_device_id | TEXT | FK to devices table |
| captured_at | TIMESTAMP NOT NULL | From EXIF — used for ordering and time window queries |
| ingested_at | TIMESTAMP NOT NULL | When Framed first processed this file |
| format | TEXT | RAF, DNG, HEIC, JPEG etc. |
| width | INTEGER | |
| height | INTEGER | |
| file_size_bytes | INTEGER | |
| stack_id | TEXT | FK to stacks — nullable if not in a stack |
| similarity_score | REAL | Score against stack centroid at time of assignment |
| vector_valid | BOOLEAN | False signals recomputation is needed |
| review_status | TEXT | unseen \| kept \| discarded |
| exif_json | TEXT | Raw EXIF blob |

**Indexes:** `captured_at`, `stack_id`, `review_status`

---

### 4.2 feature_vectors

| Column | Type | Notes |
|---|---|---|
| photo_id | TEXT PK | FK to photos |
| perceptual_hash | BLOB NOT NULL | 8 bytes — fast pre-filter |
| feature_vector | BLOB NOT NULL | 2048 x float32 — Vision.framework featurePrint |
| computed_at | TIMESTAMP NOT NULL | |

---

### 4.3 stacks

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| best_photo_id | TEXT | FK to photos |
| best_photo_source | TEXT | auto_culling \| user_selected \| taste_adjusted |
| created_at | TIMESTAMP | |
| formation_method | TEXT | auto \| manual \| suggested |
| similarity_threshold_used | REAL | Threshold at time of formation |
| feed_section_id | TEXT | FK to feed_sections — nullable below minimum threshold |

---

### 4.4 stack_edits

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| photo_id | TEXT NOT NULL | FK to photos |
| stack_id | TEXT NOT NULL | FK to stacks |
| action | TEXT NOT NULL | added \| removed \| restacked |
| actioned_at | TIMESTAMP NOT NULL | |
| previous_stack_id | TEXT | Source stack if action = restacked |

---

### 4.5 devices

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID generated on first seen |
| display_name | TEXT | e.g. 'Fuji X-T5', 'iPhone 15 Pro' |
| device_type | TEXT | camera \| phone \| scanner etc. |
| first_seen_at | TIMESTAMP | |

---

### 4.6 edits

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| photo_id | TEXT NOT NULL | FK to photos |
| created_at | TIMESTAMP | |
| edit_type | TEXT | theme \| adjustment \| geometry \| prompt |
| parameters_json | TEXT | Full edit state as JSON |
| is_active | BOOLEAN | Only one active edit chain per photo at a time |
| source | TEXT | user \| suggested |

---

### 4.7 taste_signals

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| photo_id | TEXT | FK to photos — nullable if signal is stack-level |
| stack_id | TEXT | FK to stacks — nullable if signal is photo-level |
| signal_type | TEXT | kept \| discarded \| edit_accepted \| edit_undone \| stack_modified \| best_photo_changed |
| recorded_at | TIMESTAMP | |
| metadata_json | TEXT | Extra context |

---

### 4.8 feed_sections

| Column | Type | Notes |
|---|---|---|
| id | TEXT PK | UUID |
| day_date | DATE NOT NULL | Calendar date (adjusted for post-midnight rollback) |
| label | TEXT NOT NULL | Morning, Afternoon, Evening, Night, Early morning etc. |
| starts_at | TIMESTAMP NOT NULL | captured_at of first stack in section |
| ends_at | TIMESTAMP NOT NULL | captured_at of last stack in section |
| computed_at | TIMESTAMP NOT NULL | Recomputed if day receives new photos |

---

## 5. Learning Layer

The learning layer is a lightweight on-device feedback loop that personalises culling accuracy and edit starting points over time.

It watches user behaviour: which stacks are approved, which are discarded, which edits are accepted or undone, which themes are gravitated toward, which best photo elections are overridden.

All learning is on-device. No taste data is ever transmitted externally.

**V1 behaviour:** Taste signal capture is active from day one. Learning activation — signals shifting culling weights and edit defaults — is post-V1. The dataset accumulates from day one so it is ready when activation is appropriate.

---

## 6. Decisions Log

All decisions in this log are **final for V1** unless explicitly noted.

| Decision | Choice | Rationale |
|---|---|---|
| Platform | Apple ecosystem only (Mac first) | Full use of Apple frameworks, single SwiftUI codebase |
| V1 platform | Mac only | Single device in daily use makes sync unnecessary. Mac is the ingest platform given storage constraints. |
| Unique photo ID | SHA-256 content hash | Collision-proof, handles deduplication naturally |
| Database | SQLite via GRDB | Embedded, local, fast, same schema across all Apple platforms, more control than Core Data |
| Sync | Post-V1, CloudKit when multi-device | No second device in V1. Sync adds complexity with no benefit. |
| ML framework | Vision.framework + Core ML | On-device, Neural Engine optimised, no external dependencies |
| Stacking model | Ingest-time with stored vectors | Feed query stays fast; recomputation cheap |
| Storage | Move not copy on ingest | Avoids doubling disk usage, one canonical file per photo |
| Best photo source | Tracked via best_photo_source field | Ensures user_selected is never overwritten |
| Cross-session similarity | Post-V1, separate suggestions tab | Keeps V1 scope clean; data model supports it from day one |
| Feed review model | Single feed with unseen visual indicators | Anti-overwhelm — no inbox pressure, review state is ambient |
| Inbox | Top-right button showing days with unseen content | Opt-in review focus; count in days not photos or stacks |
| Feed pagination | Keyset pagination on captured_at | Fast at any library size; avoids OFFSET slowdown |
| Feed updates | Quiet 'new photos' indicator, no auto-scroll | Avoids disrupting user's scroll position |
| Edit layer structure | Theme, Adjustments, Geometry, Prompts — all non-destructive | Clean separation of concerns; consistent parameter format |
| Theme/Adjustments relationship | Theme populates Adjustments, parks pre-Theme state. Deselect restores snapshot. | Natural workflow; no surprising resets |
| Prompt architecture | VLM translates text to Adjustment parameter values. Core Image applies. VLM never sees image. | Consistent edit pipeline. Lighter VLM task means even 0.5B tier is sufficient. |
| Geometry in V1 | Straightening only. Auto-straighten via Vision horizon detection plus manual dial. | Straightening is correction. Cropping is creative choice with more UX complexity — deferred. |
| Best image selection model | Subject-first, two-stage: identify subject → score per frame. Three layers. Vision.framework only for V1. | Consistency signals intent; inconsistency signals error. Subject-relative scoring ignores irrelevant frame area. |
| Time-of-day section model | Activity-based lull detection at ingest, fixed clock as soft guardrail. Post-midnight attaches to preceding evening. | Fixed clock is too blunt. Lull-based adapts to actual shape of each day's activity. |
| Section label threshold | Sections only render when day has 5+ stacks. Below that, day header alone is sufficient. | Section labels add value when feed is dense enough to need navigation cues. |
| Learning layer V1 behaviour | Taste signal capture active. Learning activation post-V1. | Acting on sparse early signals risks degrading quality before enough data exists. |
| Publish mode V1 | Export-to-folder of processed images. No direct platform API integrations. | Direct integrations add per-platform maintenance surface with no workflow benefit. |
| Network calls | No network calls except CloudKit sync (post-V1). On-device only. | Privacy-first principle. |
| V1 scope — in | Ingest pipeline, review feed, culling (Vision only), edit layer (Theme/Adjustments/Geometry; Prompts gated), publish mode (export-to-folder), inbox, taste signal capture | Covers the complete personal workflow from ingest to share |
| V1 scope — out | iOS/iPadOS, CloudKit sync, VLM/Prompts activation, learning layer activation, cross-session similarity, caption suggestions | Each deferred item depends on V1 proving useful, requires VLM, or needs accumulated data |
| Bundle identifier | com.vamsiys.Framed | Personal use app, single developer |
| Minimum macOS deployment target | macOS 14.0 (Sonoma) | Covers ~75–85% of active Mac users as of early 2026. Required for SwiftUI improvements (@Observable, navigation APIs) and reliable Vision.framework behaviour used in the stacking and culling pipeline |

---

## 7. Future Scope (Post-V1)

### 7.1 iOS and iPadOS

Next platform targets. Single SwiftUI codebase makes Mac work directly reusable. Ingest via Camera Connection Kit — PHPhotoLibrary and UIDocumentPickerViewController. Sync becomes relevant when a second device is in active use.

### 7.2 CloudKit Sync

Data lives in user's own iCloud account. All database tables are sync candidates except RAW files (device-local always). `taste_signals` are append-only so sync is conflict-free. `best_photo_source = user_selected` must never be overwritten by an arriving `auto_culling` value. Last-write-wins as default for all other fields.

### 7.3 VLM and Prompts

Prompt-to-parameters translation via on-device VLM. Candidates: Moondream 0.5B (~480MB), SmolVLM 256M (~300MB), SmolVLM 2.2B (~1.3GB), Florence 2 Base (~450MB), Qwen2.5-VL 3B (~2GB). All open-weights, Apache 2.0, convertible to Core ML. VLMs run on GPU via Metal on Apple Silicon, not Neural Engine. Tiered download approach: lightweight (~300–500MB) and quality (~1.2–1.3GB) tiers.

### 7.4 VLM — Best Photo Enhancement

Richer best photo selection using composition, expression, and peak moment assessment. Addresses Vision-only model weaknesses in street/documentary and action contexts. Requires VLM to see the image — separate concern from Prompts.

### 7.5 Learning Layer Activation

Taste signals accumulate from V1 day one. Activation deferred until real usage data validates the approach. Weights start neutral and must never override Layer 1 error elimination in culling. Minimum signal threshold to be determined from actual data.

### 7.6 Cross-Session Similarity

Separate tab surfacing suggested stacks across sessions. Approximate nearest neighbour — FAISS or LSH candidates. User approval required before any grouping is applied. Data model supports this from day one.

### 7.7 Publish Mode — Caption Suggestions

On-device caption and description suggestions for publish mode exports. Requires VLM. Deferred with VLM.

### 7.8 Geometry — Cropping

Deliberate creative decision with UX complexity (aspect ratios, intent). Warrants its own design pass. Deferred post-V1.

### 7.9 Motion Blur and Tilted Horizon in Culling

Require more context to distinguish intent from error reliably. Deferred until taste signal data from real usage informs the approach.

---

## Appendix A: Model Behaviour Notes

Expected best image selection quality by shoot type for the V1 Vision-only culling model.

| Shoot type | Performance | Notes |
|---|---|---|
| Portraits (single subject) | Strong | Face detection, eye openness, subject sharpness covers the key dimensions well |
| Group shots | Good | Multi-face detection, aggregate eye openness scoring picks the frame where most people look good |
| Landscape / no human subject | Reasonable | Saliency anchors the subject; sharpness and exposure assessed there. No expression or moment dimension. |
| Action / sport | Moderate | Sharpness and blur within subject region assessed. Peak moment identification requires VLM — deferred. |
| Street / documentary | Weakest | Decisive moment is not assessable without semantic understanding. Falls back to technical quality. VLM significantly improves this context. |

VLM enhancement for action and street contexts is covered in Section 7.4.
