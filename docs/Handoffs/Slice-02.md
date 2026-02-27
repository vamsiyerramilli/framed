# Slice 2 Handoff — Feed

**Status:** Complete (build verified; manual AC sign-off needed)

---

## Acceptance Criteria

- AC-2.1 — Feed renders: ✓ — builds clean, app launches, feed loads from DB
- AC-2.2 — Day grouping: ⏺ Verify visually — 2 days visible (Today + 2020-07-03)
- AC-2.3 — Time-of-day sections: ⏺ Verify visually — 4 photos on today, <5 so no section headers (correct)
- AC-2.4 — Post-midnight rollback: ⏺ Verify — insert a record with `captured_at` at 02:30 and check it groups under preceding day
- AC-2.5 — Ordering: ⏺ Verify visually — most recent day at top, photos ascending within day
- AC-2.6 — Thumbnail loading: ⏺ Verify scroll — placeholder → thumbnail, no stutter
- AC-2.7 — Device tag: ⏺ Verify visually — device tag visible on cards (Slice 1 test images have no device; tag absent is correct)
- AC-2.8 — Unseen indicator: ⏺ Verify visually — blue dot visible on all cards
- AC-2.9 — Keyset pagination: ⏺ Verify with 100+ records — scroll to bottom loads older days
- AC-2.10 — Live update banner: ⏺ Verify — insert a DB record while feed is open; banner appears; tap scrolls to top
- AC-2.11 — Empty state: ⏺ Verify — clear DB, relaunch; empty state shows
- AC-2.12 — Performance: ⏺ Verify with 500 rows

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

First task: implement perceptual hash comparison (dHash or pHash using `vImage` or manual DCT), define the similarity threshold, and write the stacking algorithm that groups photos within a time window.
