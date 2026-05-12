---
task: 5
task_name: "vocab-edit-ui"
status: planned
created: 2026-05-12
steps_total: 6
steps_completed: 0
estimated_files: 8
parallelizable_with: [6, 7]
depends_on: [4]
---

## Goal

Let the user edit a saved vocabulary entry's translation/meaning and attach a free-text note. Edits persist in CoreData and the Vocabulary list updates immediately.

## Acceptance Criteria

- [ ] Tapping a row in the Vocabulary list opens the WordLookupSheet with an "Edit" affordance.
- [ ] The user can change the translation text inline and tap a "Save" button; the new translation persists across app launches.
- [ ] The user can add or change a free-text note (multi-line); it persists across app launches.
- [ ] The Vocabulary list row reflects the updated translation immediately on dismiss.
- [ ] Editing does NOT alter the lemma or surfaceForm (those remain immutable, per Task 4 stripping rule, to keep the unique key stable).
- [ ] CoreData schema gains an optional `notes: String?` attribute on `VocabularyEntry`; lightweight migration runs cleanly on existing stores.
- [ ] Existing `VocabularyListViewModelTests` and `WordLookupViewModelTests` pass; new tests cover save and load of edited fields.

## What This Is Not

- No edit of `lemma`, `surfaceForm`, or `language`. Those define the row identity.
- No new translation re-fetch on edit ("Reset to provider value" can be reached via the existing translate path; not in scope here).
- No bulk-edit UI. One row at a time.

## Approach

- The `VocabularyEntry` CoreData entity (`Shared/Aidoku.xcdatamodeld/0.9.0.xcdatamodel/contents`) currently has `translation: String?` already mutable. Add one new optional attribute `notes: String?`. CoreData lightweight migration handles new optional attributes automatically — no migration policy needed.
- The CoreData manager extension (likely `CoreDataManager+Vocabulary.swift`, identified by the explore-agent's references) gets a single new method `updateVocabularyEntry(_ entry:, translation:, notes:)` that performs an in-context mutate + save. Reuse the same `context`/`save` pattern as the existing `upsertVocabularyEntry` (in the same extension).
- UI: extend `WordLookupSheet.swift` (the vocab-only init path at `WordLookupSheet.swift:28-32`). Add an `@State private var isEditing: Bool` and conditional TextEditor fields. When `vocabOnly == true` and the row is in vocab, show an "Edit" button in the toolbar. On tap, swap the read-only translation text and the absent notes section into TextEditors. A "Save" toolbar action calls `WordLookupViewModel.applyEdits(...)`.
- `WordLookupViewModel`:
  - Add `@Published var editableTranslation: String` and `@Published var editableNotes: String`, seeded from the entry in the `init(entry:)` initializer (lines 47-60).
  - Add `func applyEdits() async` that calls the new `CoreDataManager.updateVocabularyEntry(...)` and posts `LearnerEvents.shared.vocabChanged` so the list refreshes.
  - The translation getter on the displayed row continues to read `entry.translation` (now potentially edited).
- `VocabularyListView` already opens the sheet on row tap (line 70-72). No change needed there; it picks up the new edit UI automatically.
- `VocabRowView` (lines 91-130) displays `entry.translation` already — when edits happen, `LearnerEvents.shared.vocabChanged` triggers the list view model's `refresh()` and the row re-renders. Add a tiny notes indicator (e.g., a paperclip icon) when `entry.notes != nil`.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Editable fields | Translation/meaning + Notes (new field) | User answered Q4 |
| 2 | Where to expose the edit UI | Inside the existing `WordLookupSheet` (vocab-only mode) | Reuses the same sheet; no new view; one entry point per row |
| 3 | Edit affordance trigger | "Edit" toolbar button → in-place TextEditor; "Save"/"Cancel" toolbar buttons commit/discard | Standard iOS pattern; matches Apple Reminders, Notes, etc. |
| 4 | CoreData migration | Lightweight (optional attribute, no policy) | Adding an optional `notes: String?` qualifies |
| 5 | Notes attribute name | `notes` (singular `note` rejected — multiple sentences are common) | Convention |
| 6 | Notes rendering in list row | Small SF Symbol `note.text` when `notes != nil && !notes!.isEmpty` | Lightweight indicator without taking row height |
| 7 | Save method signature | `updateVocabularyEntry(_ entry: VocabularyEntryObject, translation: String?, notes: String?)` | Matches existing `upsertVocabularyEntry` style |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | Shared/Aidoku.xcdatamodeld/0.9.1.xcdatamodel/contents | New versioned model cloning 0.9.0; `VocabularyEntry` entity gains `<attribute name="notes" optional="YES" attributeType="String"/>`. (Convention from completed PLAN-task-2-data-model.md row 1: each schema change creates a new `0.X.Y.xcdatamodel` folder.) |
| MODIFY | Shared/Aidoku.xcdatamodeld/.xccurrentversion | Set `_XCCurrentVersionName` to `0.9.1.xcdatamodel` (was `0.9.0.xcdatamodel`). |
| MODIFY | Shared/Data/Database/Objects/VocabularyEntryObject.swift | Add `@NSManaged public var notes: String?` after line 73. |
| MODIFY | Shared/Managers/CoreData/CoreDataManager+Vocabulary.swift | Add `func updateVocabularyEntry(_ entry: VocabularyEntryObject, translation: String?, notes: String?)` — set fields on entry, save context. (Locate file via `find Shared -name 'CoreDataManager*Vocab*.swift'`.) |
| MODIFY | iOS/UI/Learner/WordLookupViewModel.swift | Add `@Published var editableTranslation: String = ""`, `@Published var editableNotes: String = ""`. Seed in `init(entry:)` (lines 47-60). Add `func applyEdits() async { ... CoreDataManager.shared.updateVocabularyEntry(entry, ...) ; LearnerEvents.shared.vocabChanged.send() }`. Hold a weak `entry: VocabularyEntryObject?` from the vocab-only init for `applyEdits` use. |
| MODIFY | iOS/UI/Learner/WordLookupSheet.swift | Add `@State private var isEditing: Bool = false` to the sheet. In the body, when `vocabOnly && viewModel.isInVocab`, wrap the translation block in a conditional: read-only `Text` or `TextField(text: $viewModel.editableTranslation)`. Add a "Notes" section (always visible in vocab-only mode) — TextEditor when editing, Text when not. Add toolbar buttons `Edit` / (`Save`+`Cancel`). On Save: `Task { await viewModel.applyEdits(); isEditing = false }`. |
| MODIFY | iOS/UI/Learner/VocabularyListView.swift | Add a small `Image(systemName: "note.text")` to the `VocabRowView` HStack when `entry.notes?.isEmpty == false`. |
| MODIFY | AidokuTests/WordLookupViewModelTests.swift | Add test: init from entry, set `editableTranslation = "new"`, call `applyEdits()`, re-fetch entry, assert `translation == "new"`. Same for notes. |

## Implementation Steps

- [ ] **Step 1: CoreData schema bump**
  - **What:** clone `Shared/Aidoku.xcdatamodeld/0.9.0.xcdatamodel/contents` into a new `0.9.1.xcdatamodel/contents` and add `<attribute name="notes" optional="YES" attributeType="String"/>` to the `VocabularyEntry` entity. Update `Shared/Aidoku.xcdatamodeld/.xccurrentversion` to point `_XCCurrentVersionName` at `0.9.1.xcdatamodel`. Add `@NSManaged public var notes: String?` after line 73 of `VocabularyEntryObject.swift`. (Convention: PLAN-task-2-data-model.md row 1 — each schema bump creates a new versioned model and updates `.xccurrentversion`.)
  - **Files:** `Shared/Aidoku.xcdatamodeld/0.9.1.xcdatamodel/contents`, `Shared/Aidoku.xcdatamodeld/.xccurrentversion`, `Shared/Data/Database/Objects/VocabularyEntryObject.swift`
  - **Verify by:** `swift build` succeeds; open a clean simulator install, then upgrade-install — no crash on launch (lightweight migration kicks in).

- [ ] **Step 2: CoreData update method**
  - **What:** add `updateVocabularyEntry(_:translation:notes:)` to `CoreDataManager+Vocabulary.swift`. Same context/save pattern as the existing `upsertVocabularyEntry`.
  - **Files:** `Shared/Managers/CoreData/CoreDataManager+Vocabulary.swift`
  - **Verify by:** unit-test round-trip: create entry, call update, fetch fresh, assert fields match.

- [ ] **Step 3: ViewModel edit state**
  - **What:** in `WordLookupViewModel.swift`, add the two `@Published` editable fields, the held `entry` reference (or capture by id and re-fetch on save), and `applyEdits()`. Ensure `init(event:)` does NOT seed editables (only the entry-init path needs them).
  - **Files:** `iOS/UI/Learner/WordLookupViewModel.swift`
  - **Verify by:** unit test `WordLookupViewModelTests.swift`: init from entry, modify editables, call `applyEdits`, fetch, assert.

- [ ] **Step 4: Sheet UI for edit mode**
  - **What:** add toolbar Edit/Save/Cancel buttons (vocab-only-mode gate), wrap translation in a conditional TextEditor, add a Notes section. Cancel reverts `editableTranslation`/`editableNotes` to the entry's persisted values. Save calls `applyEdits` and dismisses the editor (keeps the sheet open).
  - **Files:** `iOS/UI/Learner/WordLookupSheet.swift`
  - **Verify by:** open Vocabulary tab → tap entry → tap Edit → change text → Save → close sheet → reopen entry → see edited text.

- [ ] **Step 5: List row notes indicator**
  - **What:** add the SF Symbol `note.text` indicator in `VocabRowView` when notes is non-empty.
  - **Files:** `iOS/UI/Learner/VocabularyListView.swift`
  - **Verify by:** add a note via Step 4, see the icon appear in the list row.

- [ ] **Step 6: Tests + manual smoke**
  - **What:** new test cases in `WordLookupViewModelTests`; manual: add a note, kill the app, relaunch, see the note still there.
  - **Files:** `AidokuTests/WordLookupViewModelTests.swift`
  - **Verify by:** `xcodebuild test -only-testing:AidokuTests/WordLookupViewModelTests` passes.

## Testing Strategy

- Unit tests for `WordLookupViewModel.applyEdits` and the new `CoreDataManager.updateVocabularyEntry` using `makeInMemoryContainer()` (existing helper, see `VocabularyManagerTests` per graph community 9).
- Manual on-device smoke for the UI flow (TextEditor sizing, keyboard handling).

## Risks

- **Most complex:** CoreData migration. If the existing project uses versioned `.xcdatamodel` folders (one per release), adding the attribute to the active version may break the iCloud-sync schema check. Mitigation: confirm the migration policy by inspecting the model bundle; if needed, create a new versioned model and set it as current.
- **Assumption most likely wrong:** that `entry.translation` is always non-nil after the user's first translate. If translation was never fetched (offline DeepL save before translate), `editableTranslation` seeds to `""`. UI must allow saving an empty translation (delete it) without erroring.
- **Easy-to-miss edge case:** the sheet is also presented via `init(event:)` from the reader. Edit UI must be gated on `vocabOnly == true` only; otherwise it would let users edit a row they haven't even saved yet.
