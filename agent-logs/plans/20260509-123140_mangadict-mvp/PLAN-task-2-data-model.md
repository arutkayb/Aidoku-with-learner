---
task: 2
task_name: "data-model"
status: completed
created: 2026-05-09
steps_total: 8
steps_completed: 8
estimated_files: 12
parallelizable_with: [3, 4]
depends_on: [1]
---

# Task 2 — Core Data Entities + Backup Models for Vocab/Familiarity/Flashcards

## Goal

Add three new Core Data entities (`VocabularyEntry`, `FamiliarityProgress`, `FlashcardState`) plus their `CoreDataManager` extension methods and backup model structs, so subsequent tasks can persist and restore vocab data using existing Aidoku conventions.

## Acceptance Criteria

- [ ] `Aidoku.xcdatamodeld` contains a new versioned model (e.g. `0.9.0.xcdatamodel`) with three new entities defined: `VocabularyEntry`, `FamiliarityProgress`, `FlashcardState`. Existing entities and fields are unchanged.
- [ ] Auto-generated `NSManagedObject` subclass files exist at `Shared/Data/Database/Objects/VocabularyEntryObject.swift` (and the two siblings), each adding `@objc(...)` and convenience methods following the existing `MangaObject.swift` pattern.
- [ ] A new `Shared/Managers/CoreData/CoreDataManager+Vocabulary.swift` extension exposes: `getVocabularyEntry(sourceId:mangaId:lemma:)`, `createVocabularyEntry(...)`, `removeVocabularyEntry(...)`, `getAllVocabulary()`, `getFamiliarity(entryId:)`, `setFamiliarity(entryId:level:)`, `getFlashcardQueue()`, `markFlashcardReview(entryId:correct:)`, with explicit context parameter optional and threading conventions matching `CoreDataManager+Manga.swift`.
- [ ] Backup struct fields `vocabulary: [BackupVocabularyEntry]?` and `familiarity: [BackupFamiliarityProgress]?` are added to `Backup` (`Shared/Data/Backup/Backup.swift`) with corresponding `BackupVocabularyEntry.swift` and `BackupFamiliarityProgress.swift` files modeled on `BackupHistory.swift`.
- [ ] `BackupManager.createBackup()` populates the new arrays; `BackupManager` restore code path reconstructs the entities (insert-or-update by composite key).
- [ ] `BackupOptions` struct gains `includeVocabulary: Bool` defaulting to `true`.
- [ ] Lightweight migration succeeds on an existing local store: app launches with a pre-existing 0.8.2 store and the new entities are present at runtime (verified by an XCTest / Swift Testing case that fetches an empty `VocabularyEntry` list without error).
- [ ] Tests under `AidokuTests/VocabularyManagerTests.swift` cover: create / fetch / delete vocab entry, set familiarity from level 0 → 3, flashcard "correct" raises level by 1 idempotently, and a backup → restore round-trip preserves entries.
- [ ] `FlashcardState` is intentionally NOT in the backup (ephemeral review state).

## What This Is Not

- No UI changes. This task only ships data layer + backup wiring.
- No flashcard scheduling logic beyond "increment level on correct" and "max level + done lock removes from queue." Time-based scheduling and decay are explicitly out.
- No iCloud sync of vocab beyond what existing `CoreDataManager` cloud setup gives for free (Aidoku's CoreData uses NSPersistentCloudKitContainer; vocab entities go along by default unless we mark them `excluded`).
- No persistent OCR cache (deferred to v2).

## Approach

Mirror the existing CoreData entity pattern documented during exploration:

- New model version under `Shared/Aidoku.xcdatamodeld/0.9.0.xcdatamodel/contents` with `currentVersion="0.9.0.xcdatamodel"` set in `Shared/Aidoku.xcdatamodeld/.xccurrentversion`.
- Auto-generated NSManagedObject subclasses (`codeGenerationType="class"`) — Xcode generates the `+CoreDataProperties.swift` and `+CoreDataClass.swift` at build time from the model. Hand-written files at `Shared/Data/Database/Objects/Vocabulary*.swift` add `@objc(...)`, convenience init/load methods, and identifier accessors — matching `Shared/Data/Database/Objects/MangaObject.swift`.
- Manager extension `CoreDataManager+Vocabulary.swift` follows the structure of `CoreDataManager+Manga.swift`: methods take an optional `NSManagedObjectContext? = nil` and default to `container.viewContext`. Background mutations use `container.performBackgroundTask`.
- Backup struct fields modeled on `BackupHistory` (`Shared/Data/Backup/Models/BackupHistory.swift`): one `init(object:)` from CoreData and one `toObject(context:)` to CoreData.
- `BackupManager.createBackup()` (around `Shared/Data/Backup/BackupManager.swift:109-170`) gets two new array fetches conditional on `BackupOptions.includeVocabulary`.
- Lightweight migration: existing manager already sets `shouldMigrateStoreAutomatically = true` and `shouldInferMappingModelAutomatically = true` (`Shared/Managers/CoreData/CoreDataManager.swift:59-60, 67-68`). New entities with no rename/property-change should infer cleanly.

### Entity schemas

**VocabularyEntry**
- `id: UUID` (primary)
- `lemma: String` — normalized form (lowercase, trimmed) used as dedupe key
- `surfaceForm: String` — original form first encountered
- `language: String` — `"de-DE"` etc.
- `translation: String?` — last cached translation
- `dateAdded: Date`
- `dateLastSeen: Date`
- `sourceMangaId: String?` — `MangaIdentifier.mangaKey` of where it was added
- `sourceMangaSourceId: String?`
- Constraint: `(language, lemma)` unique pair (CoreData uniqueness constraint)
- Relationship: `progress: FamiliarityProgress?` (one-to-one inverse `entry`)

**FamiliarityProgress**
- `entry: VocabularyEntry` (one-to-one)
- `level: Int16` — 0…3 (0 = freshly added, 3 = mastered/done)
- `correctAnswers: Int32` — total correct flashcard reviews
- `lastReviewedAt: Date?`
- `done: Bool` — when true, entry is locked at level 3 and excluded from review queue
- Default for new rows: `level=0, correctAnswers=0, done=false`

**FlashcardState** (ephemeral; not in backup)
- `id: UUID` (primary)
- `entry: VocabularyEntry` (relationship; cascade delete from entry)
- `lastShownAt: Date?` — used to round-robin within a session
- `sessionCorrect: Int16` — within-session counter, reset between sessions

### Manager API surface

```swift
// Read
func getVocabularyEntry(language: String, lemma: String, context: NSManagedObjectContext? = nil) -> VocabularyEntryObject?
func getAllVocabulary(language: String? = nil, context: NSManagedObjectContext? = nil) -> [VocabularyEntryObject]
func getFlashcardQueue(language: String? = nil, limit: Int? = nil, context: NSManagedObjectContext? = nil) -> [VocabularyEntryObject]

// Write
@discardableResult
func upsertVocabularyEntry(language: String, lemma: String, surfaceForm: String, translation: String?, sourceMangaId: String?, sourceMangaSourceId: String?, context: NSManagedObjectContext? = nil) -> VocabularyEntryObject
func removeVocabularyEntry(_ entry: VocabularyEntryObject, context: NSManagedObjectContext? = nil)
func setFamiliarity(_ entry: VocabularyEntryObject, level: Int16, context: NSManagedObjectContext? = nil)
func markFlashcardReview(_ entry: VocabularyEntryObject, correct: Bool, context: NSManagedObjectContext? = nil)
func setDone(_ entry: VocabularyEntryObject, context: NSManagedObjectContext? = nil)  // locks at level 3
```

`markFlashcardReview` rule: if `correct == true` and `progress.done == false` and `progress.level < 3`, increment `progress.level` by 1; always increment `progress.correctAnswers` if correct; always update `progress.lastReviewedAt`.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Storage | Core Data, lightweight migration | Matches `Shared/Managers/CoreData/CoreDataManager.swift:59-60` |
| 2 | Code generation | `codeGenerationType="class"` (auto NSManagedObject) | Matches existing model |
| 3 | Hand-written subclass file | `Shared/Data/Database/Objects/VocabularyEntryObject.swift` etc. | Matches `MangaObject.swift` |
| 4 | Manager extension | `Shared/Managers/CoreData/CoreDataManager+Vocabulary.swift` | Matches `+Manga`, `+History`, `+Track` extensions |
| 5 | Dedupe key | `(language, lemma)` unique constraint | Allows same word in different languages, prevents duplicates within a language |
| 6 | Lemma normalization | Lowercase + trim whitespace at insert time | Default — Foundation Models / DeepL handle accents/case fine on output |
| 7 | Familiarity levels | `Int16`, range 0…3 | Vision doc: 3 levels + freshly-added (0) |
| 8 | Familiarity progression | Correct flashcard answer → +1, capped at 3 | Vision doc |
| 9 | Done lock | Boolean field, separate from level (level can hit 3 without `done`) | Default — distinguishes "scored 3 right" from "I'm finished with this word" |
| 10 | Backup inclusion | Vocabulary + familiarity in backup; flashcard state excluded | Default — review state is session-ephemeral |
| 11 | Backup model files | `Shared/Data/Backup/Models/BackupVocabularyEntry.swift`, `BackupFamiliarityProgress.swift` | Matches `BackupHistory.swift` |
| 12 | Cloud sync | Default — entities participate in existing `NSPersistentCloudKitContainer` setup, no opt-out | Matches existing entities; cheap to disable later |
| 13 | Test framework | Swift Testing (`import Testing`) | Matches `AidokuTests/TrackerSyncTests.swift:10` |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | `Shared/Aidoku.xcdatamodeld/0.9.0.xcdatamodel/contents` | New model version: clones 0.8.2 + adds three entities |
| MODIFY | `Shared/Aidoku.xcdatamodeld/.xccurrentversion` | Set `currentVersion="0.9.0.xcdatamodel"` |
| CREATE | `Shared/Data/Database/Objects/VocabularyEntryObject.swift` | `@objc(VocabularyEntryObject)` subclass with `identifier`, `load(from:)`, hashable identifier struct |
| CREATE | `Shared/Data/Database/Objects/FamiliarityProgressObject.swift` | Subclass; one-to-one relationship to `VocabularyEntryObject` |
| CREATE | `Shared/Data/Database/Objects/FlashcardStateObject.swift` | Subclass; cascade-delete from entry |
| CREATE | `Shared/Managers/CoreData/CoreDataManager+Vocabulary.swift` | All public manager methods listed above |
| CREATE | `Shared/Data/Backup/Models/BackupVocabularyEntry.swift` | Codable struct + `init(object:)` + `toObject(context:)`, mirrors `BackupHistory.swift` |
| CREATE | `Shared/Data/Backup/Models/BackupFamiliarityProgress.swift` | Same pattern, links to vocab by `(language, lemma)` |
| MODIFY | `Shared/Data/Backup/Backup.swift` | Add `vocabulary` and `familiarity` array properties + CodingKeys |
| MODIFY | `Shared/Data/Backup/BackupManager.swift` | Populate new arrays in `createBackup`; restore them in restore path; add `BackupOptions.includeVocabulary` (default true) |
| CREATE | `AidokuTests/VocabularyManagerTests.swift` | Swift Testing cases listed below |
| MODIFY | `Aidoku.xcodeproj/project.pbxproj` | Add new files to target membership (Aidoku app + AidokuTests for the test file) |

## Implementation Steps

### Phase A — Schema

- [x] **Step 1: Add the new model version**
  - **What:** Duplicate `0.8.2.xcdatamodel/contents` to `0.9.0.xcdatamodel/contents`, add the three `<entity>` blocks. Update `.xccurrentversion` to point to `0.9.0.xcdatamodel`.
  - **Files:** `Shared/Aidoku.xcdatamodeld/0.9.0.xcdatamodel/contents`, `.xccurrentversion`
  - **Verify by:** `xcodebuild -workspace Aidoku.xcodeproj -scheme Aidoku build` compiles. Xcode console at first launch logs lightweight migration applied.

- [x] **Step 2: Add hand-written subclass files**
  - **What:** Three `.swift` files under `Shared/Data/Database/Objects/`, each declaring the `@objc` subclass with one-line `convenience` init, `load(from:)` for upsert, and an `identifier` computed property. Match the pattern in `Shared/Data/Database/Objects/MangaObject.swift`.
  - **Files:** `VocabularyEntryObject.swift`, `FamiliarityProgressObject.swift`, `FlashcardStateObject.swift`
  - **Depends on:** Step 1
  - **Verify by:** Compile passes; classes resolve from manager extension code.

### Phase B — Manager API

- [x] **Step 3: Implement `CoreDataManager+Vocabulary.swift`**
  - **What:** All eight public methods listed in Approach. Each follows `CoreDataManager+Manga.swift` conventions: optional context arg, default to `container.viewContext`, use `try? context.fetch(request)` for reads, `try? context.save()` after writes on background context. Mutating methods that touch many rows (e.g. `removeVocabularyEntry`) use `container.performBackgroundTask`.
  - **Files:** `Shared/Managers/CoreData/CoreDataManager+Vocabulary.swift`
  - **Depends on:** Step 2
  - **Verify by:** Manually instantiate and call each method in a unit test from Step 8.

### Phase C — Backup wiring

- [x] **Step 4: Add backup model structs**
  - **What:** `BackupVocabularyEntry.swift` mirrors `BackupHistory.swift`: `Codable, Hashable, Sendable` struct with explicit fields, `init(object: VocabularyEntryObject)`, `func toObject(context: NSManagedObjectContext? = nil) -> VocabularyEntryObject`. `BackupFamiliarityProgress.swift` similarly; the `toObject` looks up the parent vocab entry by `(language, lemma)` and creates the progress relationship.
  - **Files:** Two backup model files
  - **Depends on:** Step 2, 3
  - **Verify by:** Round-trip test in Step 8.

- [x] **Step 5: Wire `Backup` and `BackupManager`**
  - **What:** Add `var vocabulary: [BackupVocabularyEntry]?` and `var familiarity: [BackupFamiliarityProgress]?` to `Backup.swift`. In `BackupManager.swift`, locate `createBackup()` (~line 109): if `BackupOptions.includeVocabulary` is true, fetch all vocab entries via `CoreDataManager.shared.getAllVocabulary()` and map to `BackupVocabularyEntry`; same for familiarity. In the restore path (find by symmetry — the existing function that calls `BackupHistory.toObject`), iterate `vocabulary` and `familiarity` arrays and call `toObject(context:)`. Add `includeVocabulary: Bool = true` to `BackupOptions`.
  - **Files:** `Shared/Data/Backup/Backup.swift`, `Shared/Data/Backup/BackupManager.swift`
  - **Depends on:** Step 4
  - **Verify by:** Round-trip test in Step 8 covers create + restore.

### Phase D — Tests + project membership

- [x] **Step 6: Add files to Xcode target**
  - **What:** Add all created `.swift` files to the `Aidoku` target (and `VocabularyManagerTests.swift` to `AidokuTests`) via `Aidoku.xcodeproj/project.pbxproj`. Easiest: open the project in Xcode, right-click → Add Files. Or hand-edit pbxproj if a script exists.
  - **Files:** `Aidoku.xcodeproj/project.pbxproj`
  - **Depends on:** Steps 2–5
  - **Verify by:** `xcodebuild -scheme Aidoku build` and `xcodebuild -scheme Aidoku test` discover the new files and tests run.

- [x] **Step 7: Wire localization stubs (placeholder strings only)**
  - **What:** Add empty entries in `Shared/Localization/en.lproj/Localizable.strings` for: `LEARNER_VOCABULARY = "Vocabulary"`, `LEARNER_VOCAB_FAMILIARITY_LEVEL = "Familiarity"`, `LEARNER_VOCAB_DONE = "Done"`. These get used in later UI tasks but stub them now so backup field display names exist.
  - **Files:** `Shared/Localization/en.lproj/Localizable.strings`
  - **Verify by:** `grep -c "^\"LEARNER_" Shared/Localization/en.lproj/Localizable.strings` returns ≥ 3.

- [x] **Step 8: Write `VocabularyManagerTests.swift`**
  - **What:** Swift Testing cases:
    1. `createAndFetch_roundTrip` — upsert an entry, fetch it back by `(language, lemma)`, assert fields match.
    2. `setFamiliarity_capsAtThree` — call `markFlashcardReview(_, correct: true)` four times, assert `level == 3`.
    3. `setDone_locksLevel` — `setDone(entry)`, assert `done == true && level == 3`; subsequent `markFlashcardReview` calls do not change level.
    4. `removeEntry_cascadesProgress` — remove entry, fetch by id returns nil; familiarity row count drops by 1.
    5. `backupRoundTrip_preservesEntries` — create 3 entries with varying familiarity, build backup struct, clear store, restore from backup, assert all 3 entries with correct familiarity exist. Use an in-memory CoreData stack — see existing `AidokuTests/TrackerSyncTests.swift` for the pattern.
  - **Files:** `AidokuTests/VocabularyManagerTests.swift`
  - **Depends on:** Steps 1–6
  - **Verify by:** `xcodebuild -scheme Aidoku test -destination 'platform=iOS Simulator,name=iPhone 16'` reports 5 passing.

## Testing Strategy

- File: `AidokuTests/VocabularyManagerTests.swift` (Swift Testing).
- 5 test cases listed in Step 8.
- Pattern: instantiate a test-only `CoreDataManager` with an in-memory `NSPersistentContainer` so tests don't pollute the real store. The existing `AidokuTests/TrackerSyncTests.swift` actor-based mocking shows the project's preferred isolation style.
- Run command: `xcodebuild -scheme Aidoku -destination 'platform=iOS Simulator,name=iPhone 16' test -only-testing:AidokuTests/VocabularyManagerTests`.

## Risks

- **Most complex part:** Backup round-trip. The familiarity-progress entity refers to its parent vocab entry by relationship; backup serialization must use the natural key `(language, lemma)` to re-link on restore (Core Data NSManagedObjectIDs aren't stable across stores). If two backups are merged, dedupe must use the same key.
- **Most-likely-wrong assumption:** That lightweight migration handles the new entities cleanly. If the existing CloudKit-enabled container has constraints on entity-rename/relationship rules, migration may fail at runtime. Mitigation: test on a real seeded 0.8.2 store (copy `Aidoku.sqlite` from a TestFlight install) before considering this task complete.
- **Edge case:** A vocab entry created on device A and a duplicate (same lemma, same language) created on device B before either device syncs. On restore, the upsert key `(language, lemma)` collapses them to one — losing whichever has the older `dateLastSeen`. Acceptable for personal use; document in Risks comment in `BackupVocabularyEntry.swift`.
