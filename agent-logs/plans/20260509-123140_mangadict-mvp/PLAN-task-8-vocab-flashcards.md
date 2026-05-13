---
task: 8
task_name: "vocab-flashcards"
status: planned
created: 2026-05-09
steps_total: 7
steps_completed: 0
estimated_files: 11
parallelizable_with: [5, 6, 7]
depends_on: [2, 3]
---

# Task 8 — Vocabulary List + Flashcard Mode

## Goal

Add a top-level "Vocabulary" tab (or library entry point) that shows all collected vocab grouped by familiarity level, and a Flashcards mode that reviews unfilled vocab and raises familiarity on correct answers.

## Acceptance Criteria

- [ ] A new `LearnerTabView` SwiftUI view exists at `iOS/UI/Learner/LearnerTabView.swift` with two segments: `Vocabulary` and `Flashcards`.
- [ ] An entry point to `LearnerTabView` is added to Aidoku's existing tab bar (alongside Library / Browse / History / Settings) — visible only when `Learner.enabledGlobally` is true (defaults to true once the user enables it for any manga).
- [ ] **Vocabulary list:**
  - Sections by familiarity level: "New (0)", "Learning (1)", "Familiar (2)", "Mastered (3)", "Done".
  - Each row shows surface form (large) + lemma + translation (subtitle) + small badge for source manga (chip).
  - Search bar filters by surface/lemma/translation substring.
  - Sort menu: by date added (newest/oldest), by alphabetical, by familiarity asc/desc.
  - Swipe-to-delete on a row removes the entry (and its progress + flashcard state).
  - Tap a row opens the same `WordLookupSheet` as Task 6 (in "vocab-only" mode that hides the "Translate sentence" button — there's no current page context).
- [ ] **Flashcards mode:**
  - Selects up to 20 entries per session: not `done`, sorted by `(level asc, lastReviewedAt asc nilsFirst)` so least-known and least-recently-seen come first.
  - Single-card UI: front shows surface form (large), back shows translation, lemma, example.
  - Tap the card to flip; "Got it" button raises level by 1 (max 3); "Still learning" button leaves level unchanged but updates `lastReviewedAt`. Both advance to the next card.
  - "Mark Done" button on the back of the card sets `done = true` and advances.
  - Session-end summary: # cards reviewed, # correct, # newly mastered (level→3 this session).
  - Empty state when queue is empty: "No words to review."
- [ ] All persistence goes through `CoreDataManager+Vocabulary` from Task 2; no direct CoreData calls in views.
- [ ] Adding/removing/levelling a word fires `LearnerEvents.shared.vocabChanged` so the reader overlay (Task 5) updates.
- [ ] Tests cover: queue ordering correctness, "Got it" raises level idempotently across re-launches, "Mark Done" excludes from queue, search/sort filtering, empty state.

## What This Is Not

- No SRS scheduling (decay, due dates) — vision doc explicit.
- No multi-language tabs — all languages shown in one list, sectioned by familiarity. (Filter by language via search if needed.)
- No CSV export, no Anki export.
- No bulk operations (multi-select delete, bulk-set-done).
- No example-sentence editing.
- No flashcard streaks / stats history.

## Approach

### Tab integration

Aidoku's tab bar lives in `iOS/UI/...` (likely a `UITabBarController` set up in `SceneDelegate.swift` or app delegate). Locate it via the existing `Browse`, `Library`, `History`, `Settings` tabs. Add a new tab item between `Library` and `Browse` (placement is reasonable — vocab is library-adjacent). The new tab's root is a `UIHostingController` wrapping `LearnerTabView`.

A small chrome guard: read `Learner.enabledGlobally` from UserDefaults; show/hide the tab on the fly when it changes. Default value is set to `true` the first time `Learner.enabled.<mangaId>` is set to `true` for any manga (Task 5 hook).

### Vocab list view

```swift
struct VocabularyListView: View {
    @Observable var viewModel = VocabularyListViewModel()
    @State var search = ""
    @State var sort: SortOption = .dateAddedDesc

    var body: some View {
        List { ... sectioned ... }
            .searchable(text: $search)
            .toolbar { sortMenu }
            .task { await viewModel.refresh() }
            .onReceive(LearnerEvents.shared.vocabChanged) { _ in
                Task { await viewModel.refresh() }
            }
    }
}
```

`VocabularyListViewModel` fetches all entries via `CoreDataManager.shared.getAllVocabulary()` and groups in-memory; no CoreData NSFetchedResultsController complication for MVP scale.

### Flashcards view

```swift
struct FlashcardsView: View {
    @Observable var viewModel = FlashcardsViewModel()

    var body: some View {
        if viewModel.queue.isEmpty { emptyState }
        else if viewModel.sessionEnded { summaryView }
        else {
            FlashcardCardView(entry: viewModel.current)
            // Got it / Still learning / Mark Done buttons
        }
    }
}
```

`FlashcardsViewModel`:

```swift
@Observable
final class FlashcardsViewModel {
    var queue: [VocabularyEntryObject] = []
    var currentIndex = 0
    var correctCount = 0
    var newlyMasteredCount = 0
    var sessionEnded = false

    var current: VocabularyEntryObject? { queue[safe: currentIndex] }

    func loadQueue() async      // builds queue from CoreData
    func gotIt() async          // markFlashcardReview(correct: true), advance
    func stillLearning() async  // markFlashcardReview(correct: false), advance
    func markDone() async       // setDone, advance
    func endSession()           // explicitly stop, show summary
}
```

Queue construction (Task 2's `getFlashcardQueue`):

```sql
-- pseudo
SELECT * FROM VocabularyEntry v
JOIN FamiliarityProgress p ON p.entry = v
WHERE p.done = false
ORDER BY p.level ASC, p.lastReviewedAt ASC NULLS FIRST
LIMIT 20
```

`getFlashcardQueue(limit:)` from Task 2 implements this.

### "Vocab-only" word sheet mode

`WordLookupSheet` from Task 6 takes a `WordTapEvent` that includes `pageContext`. Add a new init `WordLookupSheet(entry: VocabularyEntryObject)` that hides the "Translate this sentence" button and skips `loadTranslation` (uses cached translation from the entry; if nil, lazy-fetches but doesn't break). Reuse the same sheet to keep UX consistent.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Tab placement | Between Library and Browse | Default — library-adjacent feature |
| 2 | Tab visibility | Gated on `Learner.enabledGlobally` (auto-set when first manga toggle on) | Default — keeps tab bar clean for users who haven't opted in |
| 3 | Vocab list grouping | Sections by familiarity level | Default — matches mental model |
| 4 | Sort default | Date added, newest first | Default — most recent vocab top of mind |
| 5 | Search match | Substring on surface, lemma, translation | Default — broadest useful match |
| 6 | Flashcard queue size | 20 per session | Default — short enough for one-sitting review |
| 7 | Queue ordering | `level ASC, lastReviewedAt ASC NULLS FIRST` | Default — least-known, least-recent first |
| 8 | Card flip UX | Tap to flip; explicit Got it / Still learning / Mark Done buttons | Default — fewer accidental level-ups than swipe |
| 9 | Session summary | Cards reviewed, # correct, # newly mastered | Default — minimum interesting stats |
| 10 | Reuse word sheet | Yes, with `vocab-only` mode | Avoid UI duplication |
| 11 | Persistence layer | All through `CoreDataManager+Vocabulary` from Task 2 | No direct CoreData in views |
| 12 | Empty state | "No words to review." | Default — explicit feedback |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | `iOS/UI/Learner/LearnerTabView.swift` | Tab container with `VocabularyListView` and `FlashcardsView` segments |
| CREATE | `iOS/UI/Learner/VocabularyListView.swift` | List view |
| CREATE | `iOS/UI/Learner/VocabularyListViewModel.swift` | `@Observable` view model |
| CREATE | `iOS/UI/Learner/FlashcardsView.swift` | Flashcard UI |
| CREATE | `iOS/UI/Learner/FlashcardsViewModel.swift` | `@Observable` view model |
| MODIFY | `iOS/UI/Learner/WordLookupSheet.swift` | Add `init(entry: VocabularyEntryObject)` and `vocabOnly` flag that hides the "Translate sentence" button |
| MODIFY | `iOS/SceneDelegate.swift` (or wherever the tab bar is built) | Add the Learner tab between Library and Browse |
| MODIFY | `Shared/Localization/en.lproj/Localizable.strings` | `LEARNER_VOCAB_TAB_TITLE`, `LEARNER_FLASHCARDS_TAB_TITLE`, `LEARNER_VOCAB_NEW`, `LEARNER_VOCAB_LEARNING`, `LEARNER_VOCAB_FAMILIAR`, `LEARNER_VOCAB_MASTERED`, `LEARNER_VOCAB_DONE_SECTION`, `LEARNER_FC_GOT_IT`, `LEARNER_FC_STILL_LEARNING`, `LEARNER_FC_MARK_DONE`, `LEARNER_FC_EMPTY`, `LEARNER_FC_SUMMARY_TITLE`, `LEARNER_VOCAB_SEARCH`, `LEARNER_VOCAB_SORT_DATE`, etc. |
| CREATE | `AidokuTests/VocabularyListViewModelTests.swift` | Sectioning, search, sort tests |
| CREATE | `AidokuTests/FlashcardsViewModelTests.swift` | Queue ordering, level progression, session end tests |
| MODIFY | `Aidoku.xcodeproj/project.pbxproj` | Add files |

## Implementation Steps

### Phase A — View models

- [ ] **Step 1: Implement `VocabularyListViewModel`**
  - **What:** Methods: `refresh()` reloads from CoreData; `delete(entry:)` calls `removeVocabularyEntry`; computed `groupedSections(filter:sort:)` returns `[(level: Int16, entries: [VocabularyEntryObject])]`. Subscribe to `vocabChanged` in init via `AsyncStream`.
  - **Files:** `VocabularyListViewModel.swift`
  - **Depends on:** Tasks 2, 3
  - **Verify by:** Tests in step 6.

- [ ] **Step 2: Implement `FlashcardsViewModel`**
  - **What:** All methods in Approach. `loadQueue()` calls `getFlashcardQueue(limit: 20)` from Task 2. State machine: `loading → reviewing → ended`. `gotIt()`, `stillLearning()`, `markDone()` advance the index and dispatch the appropriate `markFlashcardReview` / `setDone`.
  - **Files:** `FlashcardsViewModel.swift`
  - **Depends on:** Tasks 2, 3
  - **Verify by:** Tests in step 7.

### Phase B — Views

- [ ] **Step 3: Implement `VocabularyListView`**
  - **What:** SwiftUI `List` with sectioned data; `.searchable(text:)`; toolbar sort menu; tap row → present `WordLookupSheet(entry:)` via `.sheet(item:)`.
  - **Files:** `VocabularyListView.swift`
  - **Depends on:** Step 1, modified `WordLookupSheet`
  - **Verify by:** Compile + preview.

- [ ] **Step 4: Implement `FlashcardsView`**
  - **What:** SwiftUI view with three states. Card flip via `.rotation3DEffect(...)`. Buttons trigger view-model methods.
  - **Files:** `FlashcardsView.swift`
  - **Depends on:** Step 2
  - **Verify by:** Compile + preview.

- [ ] **Step 5: Add `LearnerTabView` and tab-bar integration**
  - **What:** `LearnerTabView` is a `TabView` with two children. In the tab-bar setup (locate where `LibraryViewController` is registered in `SceneDelegate.swift` or equivalent), insert a new `UIHostingController(rootView: LearnerTabView())` with title `NSLocalizedString("LEARNER_TAB_TITLE")` and SF Symbol `book.closed`. Conditionally include based on `UserDefaults.standard.bool(forKey: "Learner.enabledGlobally")`. In Task 5's per-manga toggle handler, set this flag to true the first time it's enabled.
  - **Files:** `LearnerTabView.swift`, `SceneDelegate.swift` (or wherever tabs live)
  - **Depends on:** Steps 3, 4
  - **Verify by:** Manual smoke — enable Learner in any manga, restart app, verify the new tab appears.

- [ ] **Step 6: Modify `WordLookupSheet` for vocab-only mode**
  - **What:** Add init `WordLookupSheet(entry: VocabularyEntryObject, vocabOnly: Bool = true)`. When `vocabOnly`, hide "Translate this sentence" button.
  - **Files:** `iOS/UI/Learner/WordLookupSheet.swift`
  - **Depends on:** Task 6
  - **Verify by:** Compile + preview.

### Phase C — Tests

- [ ] **Step 7: Tests**
  - **What:** Two test files:
    - `VocabularyListViewModelTests`: `refresh_loadsAllEntries`, `groupedSections_orderedByLevel`, `delete_removesAndPropagates`.
    - `FlashcardsViewModelTests`: `loadQueue_ordersByLevelThenLastReviewed`, `gotIt_raisesLevel_capAt3`, `markDone_excludesFromFutureQueue`, `endsSession_afterLastCard`, `emptyVocab_endsSessionImmediately`.
  - **Files:** `VocabularyListViewModelTests.swift`, `FlashcardsViewModelTests.swift`
  - **Depends on:** Steps 1, 2
  - **Verify by:** `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/VocabularyListViewModelTests -only-testing:AidokuTests/FlashcardsViewModelTests` passes.

## Testing Strategy

- Files: `AidokuTests/VocabularyListViewModelTests.swift`, `AidokuTests/FlashcardsViewModelTests.swift`.
- In-memory CoreData stack (same pattern as Task 2's tests).
- Manual smoke after Step 5: end-to-end add words via reader (Task 6), open Vocabulary tab, run flashcards through.
- Run command: `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/VocabularyListViewModelTests -only-testing:AidokuTests/FlashcardsViewModelTests`.

## Risks

- **Most complex part:** Tab-bar integration discoverability. Aidoku's tab bar setup may live in a UIKit-style `UITabBarController` configured in `SceneDelegate.swift` or a custom `RootViewController` — the exact file/method needs locating during execution. Mitigation: as a step-0 of execution, grep for `UITabBarController` and `tabBar` in `iOS/`, find the registration site, and add the new entry following the same idiom.
- **Most-likely-wrong assumption:** That a queue size of 20 fits the maintainer's habit. Could be too long (fatigue) or too short (not enough review). Mitigation: queue size is hardcoded `20` in `getFlashcardQueue(limit:)`; a future setting `Learner.flashcardSessionSize` is trivial to add.
- **Edge case:** A user-added word that the translation service couldn't translate (entry persisted with `translation == nil`). Vocab list shows "no translation cached"; flashcards show the surface form on both sides. Add a "Refetch translation" affordance in `WordLookupSheet`'s vocab-only mode for these.
