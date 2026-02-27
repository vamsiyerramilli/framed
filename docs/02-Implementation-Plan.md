# Framed — Overall Implementation Plan

**Type:** Engineering reference for Claude Code sessions  
**Approach:** Vertical slices — each slice produces a runnable, testable increment  
**Engineer:** Claude Code  
**QA:** Acceptance criteria embedded in each slice definition

---

## Guiding Principles for This Build

### Why vertical slices

Framed has real complexity at every layer: the ingest pipeline, the Vision.framework ML model, the feed architecture, the edit rendering pipeline. Building these in isolation (database first, then ML, then UI) produces a lot of work that cannot be tested until late. Worse, it produces architectural decisions that cannot be validated until you have something to actually use.

The vertical slice approach builds one complete user journey to a working state before starting the next. Each slice ends with something you can run and use. Bugs and architectural problems are caught early when they are cheapest to fix.

### One slice per Claude Code session

Each slice is scoped to fit within a Claude Code working session. Starting a new slice means starting a new session with the PRD, the current codebase, and the slice's acceptance criteria as context. This prevents context collapse — the model losing the thread of architectural decisions mid-session.

The corollary: **never start a new slice on an uncommitted, failing foundation.** Each slice must pass its acceptance criteria and be committed before the next begins.

### Acceptance criteria are the QA function

There is no human tester. The acceptance criteria for each slice are the test plan. They are written as concrete, observable outcomes — not vague descriptions of correctness. Before starting a session, confirm the criteria. Before ending a session, verify each one.

### Architectural decisions are frozen

The PRD decisions log contains all major technical choices. They are final for V1. Claude Code will sometimes suggest plausible alternatives — Core Data instead of GRDB, a different stacking approach, auto-applying edits, adding a network call for some convenience. These suggestions should be declined. If it is in the decisions log, it is decided.

---

## The Eight Slices

### Slice 1 — Foundation
**The SD card to database path**

Xcode project structure, SwiftUI app shell, full GRDB schema creation and migration, DiskArbitration SD card detection, file move with SHA-256 deduplication, photo record written to database. The pipeline runs end to end. Nothing visual yet.

**Ends with:** Plug in an SD card. A photo record appears in the database.

---

### Slice 2 — Feed
**See your photos**

Read from the database, render the review feed. Day groups with date headers. Time-of-day section labels (activity-based). Photo thumbnails. Device tags. Keyset pagination. GRDB ValueObservation for live updates. Unseen visual indicator. Empty state. No stacking yet — every photo is an individual card.

**Ends with:** Plug in an SD card, open the app, see your photos in a feed in the order they were taken.

---

### Slice 3 — Stacking
**Collapse similar photos**

Vision.framework featurePrint analysis (Stage 3 of pipeline). Perceptual hash. Cosine similarity. Connected-components grouping. Stack assignments written to database. Feed updated to show stacks collapsed to a representative photo (best by sharpness, simple placeholder until Slice 4). Recomputation from stored vectors without re-analysis.

**Ends with:** 200-photo burst collapses to approximately 15 stacks in the feed.

---

### Slice 4 — Best Photo Selection
**The culling intelligence**

Full two-stage subject-first culling model (Stage 5 of pipeline). Stage 1: saliency + face detection across the stack, subject region establishment, pattern recognition. Stage 2: per-frame scoring against subject region. Layer 1 error elimination. Layer 2 ranking by sharpness, exposure, eye openness. Layer 3 taste weight scaffolding (inactive, weights neutral). `best_photo_source` field protection — `user_selected` never overwritten.

**Ends with:** For portrait and group stacks, the right photo surfaces reliably. For landscapes, the sharpest well-exposed frame surfaces. Layer 1 correctly deprioritises out-of-focus and severely over/underexposed frames.

---

### Slice 5 — Review Interactions
**Complete a cull session**

Mark kept / discarded — photo record updated in database, visual treatment updated in feed. Manual stack management: promote best photo, add/remove from stack. Stack edits recorded in `stack_edits` table. Taste signals recorded to `taste_signals` table (inactive — recording only). Inbox button and count (days with unseen content). Inbox view (focused, unseen-only, stacks collapsed to best photo). Inbox count real-time update via GRDB observation.

**Ends with:** A complete cull session can be run start to finish. Keep/discard, manual stack overrides, inbox all work correctly.

---

### Slice 6 — Edit Layer
**Non-destructive editing**

Themes (4–5 presets, hand-crafted parameter bundles). Adjustments panel (6 sliders: warmth, contrast, fade, grain, vignette, saturation). Core Image rendering pipeline. Non-destructive edit storage as JSON in `edits` table. Theme/Adjustments interaction: Theme populates Adjustments, parks pre-Theme state, deselect restores snapshot, in-Theme tweaks discarded on deselect. Geometry (straighten): auto-straighten via Vision horizon detection, manual dial, persists across Theme changes. Prompts: input field visible, "requires enhanced model" gate, no VLM in V1. Original file provably never modified.

**Ends with:** Full non-destructive edit workflow. Theme → tweak → deselect → state restored correctly. Edits persist across sessions. Original file unchanged.

---

### Slice 7 — Share and Export
**Ingest to share, complete**

Quick share: native macOS share sheet with processed image (edits applied). Publish mode: multi-photo selection, optional title and description, export folder of full-resolution processed images with all active edits applied. No network calls. Works fully offline.

**Ends with:** Complete workflow from SD card ingest to share/export. The core personal use case is fully functional.

---

### Slice 8 — Polish and Hardening
**V1 is actually done**

Watched folder source (FSEvents). Photos library source (PHPhotoLibrary change observer). Pipeline resumability: sleep/wake, app background/foreground tested at each stage. Large library performance: 1000+ photos, scroll performance, feed query speed. Edge cases: empty states, re-insertion safety, corrupted/unreadable files. Settings screen: storage path, stacking threshold, time window, sources configuration.

**Ends with:** V1 is complete. All three ingest sources work. Pipeline resumes correctly from any interruption point. Performance is acceptable on target hardware.

---

## Technology Stack Summary

| Layer | Technology | Notes |
|---|---|---|
| UI | SwiftUI | Mac first. Single codebase for iOS/iPadOS later. |
| Language | Swift | Structured concurrency throughout (async/await, task groups) |
| Database | GRDB (SQLite) | Embedded. No network. Same schema across platforms. |
| ML/Vision | Vision.framework | featurePrint, face detection, saliency, horizon detection |
| Image Rendering | Core Image | All edit rendering. Non-destructive. |
| SD Card Detection | DiskArbitration | Mac only in V1 |
| Folder Watching | FSEvents | Mac only in V1 |
| Photos Library | PHPhotoLibrary | Change observer |
| Sync | — | Post-V1. CloudKit when multi-device. |
| Network | None | No network calls in V1. |

---

## Database Schema Summary

Eight tables. Schema is fixed — see PRD Section 4 for full column definitions.

- `photos` — one record per file, SHA-256 PK
- `feature_vectors` — separated for query performance, one per photo
- `stacks` — one per group, tracks best_photo_id and source
- `stack_edits` — operational log of manual add/remove/restack actions
- `devices` — one per camera/phone seen
- `edits` — non-destructive edit chain per photo
- `taste_signals` — observational learning data, captures from day one
- `feed_sections` — pre-computed time-of-day section boundaries per day

---

## Session Startup Checklist

At the start of every Claude Code session:

1. Provide the PRD (`01-PRD.md`)
2. Provide this implementation plan (`02-Implementation-Plan.md`)
3. Provide the slice definitions file (`03-Slice-Definitions.md`)
4. Provide the instructions file (`04-Instructions.md`)
5. State which slice is being worked on
6. State what was committed at the end of the previous session
7. Confirm the acceptance criteria for this slice

Never begin coding without completing this checklist. The context set is the architectural memory for the session.

---

## Commit Protocol

Each slice must:
1. Pass all acceptance criteria
2. Build without warnings (treat warnings as errors for V1)
3. Be committed with a message format: `[Slice N] Description — all acceptance criteria passing`

Never carry uncommitted work into a new session.

---

## What Success Looks Like at V1 Complete

- Plug in an SD card → photos appear in the feed, automatically stacked and culled, with the best frame on top
- Cull a 200-photo shoot in under 5 minutes of active review time
- Apply a theme and tweak → export a folder of full-resolution processed images
- Entire workflow works with no network connection
- Original RAW files are provably never modified
- App resumes cleanly from sleep, crash, or backgrounding at any pipeline stage
