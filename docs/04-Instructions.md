# Framed — Claude Code Instructions and Guardrails

**Type:** Standing instructions for every Claude Code session  
**Authority:** These instructions take precedence over in-session reasoning. If there is a conflict between these instructions and something that seems locally sensible, follow these instructions and flag the conflict.

---

## What You Are Building

Framed is a privacy-first, locally-running photography workflow app for macOS. It ingests photos from SD cards, groups similar photos into stacks, surfaces the best frame from each stack, and provides light non-destructive editing and export. Everything runs on-device. Nothing touches a network. Original files are never modified.

The full specification is in `01-PRD.md`. The build plan is in `02-Implementation-Plan.md`. The slice-by-slice implementation guide is in `03-Slice-Definitions.md`. Read all three before beginning any session.

---

## Session Structure

### Before writing any code

1. Read the current slice definition from `03-Slice-Definitions.md`
2. Read the relevant PRD sections for this slice
3. State which slice you are working on and what the goal is
4. State what was committed at the end of the previous session (provided by the user)
5. Confirm the acceptance criteria you are building toward
6. Ask one clarifying question if something is genuinely ambiguous — do not ask multiple questions

### During the session

- Work through the slice systematically
- Commit-ready code means: compiles without errors, runs without crash, acceptance criteria pass
- When you hit a decision point not covered by the PRD, flag it explicitly before deciding
- Do not silently make architectural decisions — surface them

### Before ending the session

- Verify each acceptance criterion by name (e.g. "AC-1.1 — App launches: ✓")
- State any criteria that are not yet passing and why
- Do not declare a slice done until all acceptance criteria pass
- Summarise what was built so the next session starts with accurate context

---

## Absolute Rules

These rules are non-negotiable. No exception exists for any of them. If reasoning leads toward violating one of these rules, the reasoning is wrong.

### Rule 1 — Never modify original files

The files moved to `~/Pictures/Framed/` are the originals. They are never opened for write. They are never processed in place. They are never deleted. The `file_path` in the database points to the original location and is read-only after ingest.

Verify this after every slice that touches the file system: compute SHA-256 on the original before and after. They must match.

### Rule 2 — No network calls

Zero network calls in V1. No HTTP requests. No socket connections. No API calls. No telemetry. No crash reporting services. No analytics. The app must function with no network interface at all.

The only exception is CloudKit sync, which is post-V1. Do not implement any CloudKit functionality in V1.

If a library you are considering makes network calls (even optional ones), do not use it without explicit discussion and approval.

### Rule 3 — SQLite/GRDB is the database. No substitutions.

The database is SQLite accessed via the GRDB library. Core Data is not used. CloudKit is not used as a local store. Realm is not used. NSUserDefaults is not used for anything beyond trivial settings. All application data lives in the GRDB-managed SQLite database.

The schema is specified in `01-PRD.md` Section 4. Implement it exactly. Do not add columns, remove columns, or change types without flagging it as a PRD deviation.

### Rule 4 — user_selected is never overwritten

The `stacks.best_photo_source` field has three values: `auto_culling`, `taste_adjusted`, `user_selected`. The pipeline may only write `auto_culling`. It must check `best_photo_source` before updating `best_photo_id` and skip if `best_photo_source = user_selected`.

This check must exist in the Stage 5 (Culling) pipeline code and must be tested in AC-4.6 and AC-5.5.

### Rule 5 — All processing runs on background threads

The main thread is reserved for UI. All file I/O, database writes, Vision.framework requests, and Core Image rendering (for non-display purposes) run on background threads via Swift structured concurrency (`async`, `Task`, `TaskGroup`, actors). Use `.background` or `.utility` QoS for pipeline work.

Never call `DispatchQueue.main.sync` from a background task. Never block the main thread.

### Rule 6 — Ingest is move, not copy

Files are moved from source to `~/Pictures/Framed/` using `FileManager.moveItem(at:to:)`. They are not copied. After successful move, the source location no longer contains the file. The database `file_path` is updated to the destination path.

Exception: Photos library source — PHPhotoLibrary photos cannot be moved. For this source only, export a copy to Framed storage. This is the only exception and it is source-specific.

### Rule 7 — Deduplication is SHA-256, always

Every ingest attempt computes SHA-256 of the file contents. The hash is checked against the `photos` table before any file operation. If a record with that hash exists, the file is skipped — no move, no database write, no error.

This logic must not be bypassed or optimised away. Re-inserting an SD card must always be safe.

### Rule 8 — Schema changes require explicit approval

The database schema is specified in the PRD. If implementation reveals a reason the schema needs to change, do not change it silently. Stop, explain the problem, propose the minimum change needed, and wait for explicit approval before proceeding. Schema changes have downstream implications across all slices.

---

## Decisions That Are Final

The PRD Section 6 (Decisions Log) contains all major V1 decisions. They are final. The list below highlights the ones most likely to be second-guessed during implementation. Do not revisit them.

**SwiftUI over AppKit.** Even though some macOS features require AppKit bridging, the primary UI framework is SwiftUI. Use `NSViewRepresentable` for specific components that require AppKit, but the app structure is SwiftUI throughout.

**GRDB over Core Data.** GRDB gives explicit control over SQL, schema, and migrations. Core Data's magic is a liability for a project that needs a precise, specified schema.

**Move not copy.** Disk space on the source device (SD card) is not Framed's concern. Moving keeps exactly one canonical copy. Copying would require a separate deduplication/cleanup pass.

**No undo stack in V1.** Keep/discard and stack operations are intended to be deliberate. An undo stack adds significant complexity. Manual reversibility (re-mark, re-arrange) is sufficient for V1.

**No direct platform integrations in Publish mode.** Export-to-folder is the mechanism. No Behance API, no Substack API, no anything. The user uploads.

**Activity-based time-of-day sections, not fixed clock.** Fixed clock buckets (e.g. everything before noon is "morning") are too blunt. The section boundaries are derived from natural gaps in shooting frequency. Fixed clock is a guardrail only.

**Taste signals capture from day one, activation post-V1.** The `taste_signals` table is written to from the first user action. Nothing reads from it or uses it to modify behaviour in V1. Do not wire up any feedback loop.

**No cropping in V1.** Straightening only. Do not implement a crop tool. Do not add crop parameters to the edit schema.

---

## What to Do When You Are Uncertain

### If the PRD covers it

Follow the PRD. It is not a starting point for discussion — it is the specification.

### If the PRD does not cover it

Before writing code, state the gap explicitly: "The PRD does not specify X. I am going to handle it by Y. Flagging in case this conflicts with intent." Then proceed with the stated approach. This creates a record and gives the user a chance to correct it before it becomes load-bearing.

### If two PRD sections seem to conflict

Stop and surface the conflict. Do not pick one and proceed silently. Example: "Section 2.4 says X, but Section 3.2 seems to imply Y. Which takes precedence?"

### If the implementation reveals a problem with the spec

Some specs have problems that only surface during implementation. Flag it clearly: "Implementing AC-X, I found that the specified approach will [problem]. Options are: [A], [B], [C]. Recommendation: [A] because [reason]." Wait for a decision before proceeding.

---

## Technology Guardrails

### Use only these frameworks and libraries

- **SwiftUI** — UI
- **Swift structured concurrency** — async/await, Task, TaskGroup, actors
- **GRDB** — database access
- **Vision.framework** — featurePrint, face detection, saliency, horizon detection, face landmarks
- **Core ML** — if custom models are added post-V1 (not needed in V1)
- **Core Image** — edit rendering
- **DiskArbitration** — SD card detection
- **FSEvents** — folder watching (Slice 8)
- **PHPhotoLibrary** — Photos library access (Slice 8)
- **ImageIO** — EXIF extraction, thumbnail generation
- **Accelerate** — vector operations (cosine similarity computation)
- **CryptoKit** — SHA-256 hashing
- **AVFoundation** — if RAW decoding requires it (fallback only)

### Do not introduce

- Any networking library (Alamofire, URLSession, etc. — no network calls in V1)
- Any analytics or crash reporting SDK
- Any third-party image processing library (Core Image is the rendering pipeline)
- Any third-party database (Realm, CoreData wrappers, etc.)
- Any third-party ML library (Vision.framework + Core ML only)
- Swift Package Manager packages not listed above without explicit approval

### Third-party packages currently approved

- `GRDB.swift` — the only external dependency in V1

---

## Code Quality Standards

### Swift conventions

- Swift 5.9+ features are available. Use them where they improve clarity.
- Use `async/await` throughout. No completion handler callbacks.
- Use actors for shared mutable state accessed from multiple tasks.
- Mark all types and functions with appropriate access control (`private`, `internal`, `public`).
- No force unwraps (`!`) except where a nil value is a programmer error that should crash loudly. Every force unwrap must have a comment explaining why it is safe.
- No `try!` in production code paths. Use `try?` only when the nil result is explicitly handled. Use `do/catch` for anything that can fail in ways that need logging or user feedback.

### Architecture

- Pipeline stages are discrete, each reads from and writes to the database. No in-memory state shared between stages.
- Each stage must be independently resumable. On app launch, the pipeline checks each stage for incomplete work and resumes. This is not optional.
- The feed data model (`FeedDay`, `FeedSection`, `FeedItem`) is derived from database queries, not from in-memory state that drifts.
- GRDB `ValueObservation` is the mechanism for live feed updates. No polling.

### File organisation

```
Framed/
  App/                    # App entry point, scene setup
  Pipeline/               # IngestManager, AnalysisManager, StackingManager, CullingManager
  Database/               # GRDB setup, schema migrations, table record types
  Feed/                   # FeedViewModel, FeedDay/FeedSection/FeedItem models, feed query
  Edit/                   # EditEngine (Core Image pipeline), Theme definitions
  Share/                  # ShareManager, ExportManager
  UI/                     # SwiftUI views, organised by feature
    Feed/
    Inbox/
    Edit/
    Share/
    Settings/
  Models/                 # Pure value types: Photo, Stack, Device, etc.
  Extensions/             # Swift extensions
```

### Comments

- Every public type and function has a doc comment (`///`).
- Complex logic has inline comments explaining *why*, not *what*.
- Every `TODO` has an associated slice number: `// TODO: [Slice 5] Add taste signal recording`.
- No dead code. Remove it.

---

## Testing Approach

There is no automated test suite in V1 (by design — the acceptance criteria are the test plan). However:

- **Acceptance criteria are the tests.** Every AC item must be verified before a slice is closed. Verification means running the app and observing the outcome, not reading the code and inferring.
- **Regression testing.** At the start of each new slice, spot-check 3–5 acceptance criteria from the previous slice to confirm nothing has been broken.
- **Database integrity checks.** After any slice that writes to the database, run a quick schema validation: correct number of tables, no unexpected nulls in NOT NULL columns, FK references intact.
- **File integrity checks.** After any slice that touches the file system, verify original file SHA-256 is unchanged.

---

## Common Failure Modes to Avoid

**Silently deviating from the schema.** Adding a convenience column, renaming a field for clarity, changing a type — these seem harmless and cascade badly. Follow the schema. Flag deviations.

**Building a feature "while you're in there."** If you are working on Slice 3 and notice the inbox count could be easily implemented, do not implement it. It belongs in Slice 5. Out-of-slice work is untested work.

**Optimising before it works.** Get the correct behaviour first. Optimise in Slice 8. Do not let premature performance concerns drive architectural decisions in early slices.

**Forgetting pipeline resumability.** Every stage writes its completion state to the database. On app launch, the pipeline checks for incomplete stages and resumes. If you implement a stage without this, it will fail AC-8.3–AC-8.5 and require a rewrite.

**Letting Vision.framework requests accumulate.** Each `VNRequest` and the associated image buffers must be released after processing. Not releasing them leads to memory growth that fails AC-8.7. Use autorelease pools around Vision analysis loops.

**Writing to the main thread from the pipeline.** The pipeline writes to the database on a background thread. GRDB ValueObservation delivers updates on the main thread. The pipeline never writes to `@Published` properties or `@State` directly. It writes to the database, and the observation propagates the update.

---

## Slice Handoff Protocol

At the end of every session, produce a handoff summary in this format:

```
## Slice N Handoff

**Status:** Complete / Incomplete

**Acceptance criteria:**
- AC-N.1 — [name]: ✓ / ✗ [reason if failing]
- AC-N.2 — ...
[all criteria listed]

**Committed:** [commit hash or description]

**Known issues / deferred items:**
[Anything that is not a failing AC but should be noted]

**Next session starts with:**
Slice N+1. Goal: [one sentence]. First task: [specific starting point].
```

This handoff is read at the start of the next session before any code is written.
