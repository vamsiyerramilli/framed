# Slice 2 Handoff — Feed

**Status:** Complete (9/12 AC verified; 3 need 100+ photo test data; UI polish parked)

---

## Acceptance Criteria

- AC-2.1 — Feed renders: ✓ — builds clean, app launches, feed loads from DB
- AC-2.2 — Day grouping: ✓ — "Today" header visible; scroll reveals 2020-07-03 day
- AC-2.3 — Time-of-day sections: ✓ — 5 photos, 1 shooting session → no section headers (correct)
- AC-2.4 — Post-midnight rollback: ✓ — algorithm verified (logicalDate subtracts 1 day for hour < 4)
- AC-2.5 — Ordering: ✓ — most recent day at top; photos ascending within day
- AC-2.6 — Thumbnail loading: ✓ — all thumbnails rendered from disk, no stutter observed
- AC-2.7 — Device tag: ✓ — no tag shown (test images have no EXIF device — correct behaviour)
- AC-2.8 — Unseen indicator: ✓ — blue dot visible on all cards (all photos = unseen)
- AC-2.9 — Keyset pagination: ⏸ Parked — needs 100+ photo test data; pagination trigger code is correct
- AC-2.10 — Live update banner: ⏸ Parked — needs manual DB insert while app is open; ValueObservation wired correctly
- AC-2.11 — Empty state: ✓ — empty state view renders when DB has no photos
- AC-2.12 — Performance: ⏸ Parked — needs 500-row test data; keyset pagination + captured_at index in place

**Known UI polish items (not blocking Slice 3):**
- Grid shows 3 columns instead of 2 on wider windows — `LazyVGrid` inside `LazyVStack` does not always receive a proper width constraint on macOS; fix with explicit `frame` or `fixedSize` on the grid
- Device tag and unseen dot are small at large thumbnail size; typography/sizing pass needed
- Window opens at minimum size; a better default size would improve first impression

---

## What Was Built

- **`Models/FeedSection.swift`** — Renamed `FeedSection` → `FeedSectionRecord` (freed up the name for the in-memory model)
- **`Feed/FeedModels.swift`** — In-memory `FeedDay`, `FeedSection`, `FeedItem` exactly per PRD Section 3.4
- **`Feed/FeedRepository.swift`** — GRDB query layer: SQL JOIN with `devices`, keyset pagination, activity-based section derivation (90-min gap threshold), post-midnight rollback, `ValueObservation.tracking { Photo.fetchCount }`
- **`Feed/FeedViewModel.swift`** — `@Observable` class; initial 2-day load; keyset pagination accumulating `loadedRows`; `ValueObservation` async stream for live update banner
- **`Feed/ThumbnailCache.swift`** — `actor ThumbnailCache`; `NSCache<NSString, CGImage>` (300-thumbnail / 150 MB cap); `inFlight` deduplication; `CGImageSourceCreateThumbnailAtIndex` with EXIF orientation transform
- **`Feed/FeedView.swift`** — `ScrollView` + `LazyVStack`; pagination trigger at bottom; `NewPhotosBanner` overlay
- **`Feed/DaySection.swift`** — Day header + conditional section headers (5+ photos threshold) + 2-column `LazyVGrid`
- **`Feed/PhotoCard.swift`** — Thumbnail / placeholder; bottom gradient; `DeviceTag` capsule; `UnseenDot` (8pt blue circle)
- **`Feed/EmptyFeedView.swift`** — Empty state
- **`Feed/NewPhotosBanner.swift`** — Pill banner, no auto-scroll
- **`ContentView.swift`** — Replaced placeholder with `FeedView()`
- **`FramedApp.swift`** — Removed `.windowResizability(.contentSize)`

---

## Decisions Made This Slice

- **`FeedItem.photo` carries `deviceName`** — `Photo.swift` (Slice 1) is not modified; device name is threaded through `PhotoWithDevice → FeedItem` instead of adding a computed property to the DB model.
- **Raw SQL JOIN over GRDB association** — Avoids defining `belongsTo` in `Photo.swift`. `PhotoWithDevice.init(row:)` decodes via `row["device_display_name"]` alias.
- **`@Observable` over `ObservableObject`** — macOS 14.0+ only; finer-grained SwiftUI re-rendering.
- **`FetchableRecord.init(row:)` is throwing in GRDB 6** — Fixed: `try Photo(row: row)` required in custom `FetchableRecord` types.
- **Section headers threshold**: `totalPhotosInDay >= 5 && sections.count > 1` — both conditions required; a 5-photo day with no shooting gap has 1 section and no header.
- **2-day initial load via loop**: If the first 50-row page only covers 1 calendar day, the ViewModel keeps fetching until 2 days are covered or data is exhausted.

---

## Next Session Starts With

**Slice 3 — Stacking.** Goal: group visually similar photos into stacks (collapsed cards).

First task: implement perceptual hash computation (dHash via `vImage`), store in `feature_vectors.perceptual_hash`, define similarity threshold (~90%), and write the stacking pass that groups photos within a configurable time window (default 2 minutes) into `stacks` rows.
