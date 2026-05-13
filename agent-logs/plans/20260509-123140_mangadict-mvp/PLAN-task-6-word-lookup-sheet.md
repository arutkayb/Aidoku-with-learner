---
task: 6
task_name: "word-lookup-sheet"
status: planned
created: 2026-05-09
steps_total: 6
steps_completed: 0
estimated_files: 7
parallelizable_with: [7]
depends_on: [2, 3, 5]
---

# Task 6 — Word Lookup Bottom Sheet

## Goal

When the user taps a word in the reader, present a bottom sheet showing the word, its translation, an "Add to vocab" / "In vocab" toggle, familiarity controls, and a "Translate sentence" affordance — all driven by the `wordTapped` event from Task 5.

## Acceptance Criteria

- [ ] A SwiftUI `WordLookupSheet` view exists at `iOS/UI/Learner/WordLookupSheet.swift` and is presented as a `.sheet(isPresented:)` from a small invisible coordinator view hosted by `ReaderViewController`.
- [ ] The sheet opens within ≤300 ms of tapping a word region (from Task 5's `wordTapped` event).
- [ ] Sheet contents:
  - The tapped word in large type (the surface form, exactly as recognized).
  - The lemma below it (lowercased trimmed) if different.
  - Translation (loading spinner → translation text); errors show a localized message.
  - "Add to vocab" button if not already in vocab; toggles to "In vocab" with familiarity dot picker once added.
  - Familiarity dot picker (4 dots: 0–3) for in-vocab words; tapping a dot calls `setFamiliarity`.
  - "Mark Done" button for in-vocab words; sets `done = true` (level 3 lock).
  - "Translate sentence containing this word" button — emits `LearnerEvents.shared.sentenceTranslateRequested(for: word)` and dismisses; Task 7 handles.
- [ ] Sheet height: medium detent by default, large detent on drag.
- [ ] Sheet uses Aidoku's `MarkdownView` (already imported in `ReaderPageView.swift:10`) for the example-sentence field if Foundation Models returned one.
- [ ] After "Add to vocab" tap, `LearnerEvents.shared.vocabChanged.send()` fires so the overlay re-renders with badges.
- [ ] If the same word is tapped twice in a session (and Task 3's translation cache is warm), the sheet displays without a loading state.
- [ ] Tests cover: view-model loads translation on appear, "Add to vocab" persists via `CoreDataManager.shared.upsertVocabularyEntry`, familiarity dot tap persists, translation error states render the right localized strings.

## What This Is Not

- No editing of the lemma or translation text. The sheet is read-mostly; the only writes are vocab membership and familiarity.
- No cross-reference / dictionary lookups (definitions, conjugations, etymology). MVP shows only what the translation service returns.
- No history of past tapped words inside the sheet.
- No image / pronunciation audio.

## Approach

### Presentation

`ReaderViewController` already presents sheets (e.g., `ReaderSettingsView`, `ReaderChapterListView` at lines 502 and 525). The pattern: build a SwiftUI view, wrap in `UIHostingController`, `present(_, animated:)`. We use the same.

Subscription happens in a small SwiftUI coordinator placed in the reader view tree (or via a `UIHostingController` overlay); we use a simpler approach: `ReaderViewController` directly subscribes to `LearnerEvents.shared.wordTapped` in `viewDidLoad` and on each event presents the sheet.

```swift
private var wordTapSubscription: AnyCancellable?

override func viewDidLoad() {
    super.viewDidLoad()
    wordTapSubscription = LearnerEvents.shared.wordTapped
        .receive(on: DispatchQueue.main)
        .sink { [weak self] event in self?.presentWordLookup(event) }
}

private func presentWordLookup(_ event: WordTapEvent) {
    let vc = UIHostingController(
        rootView: WordLookupSheet(event: event, manga: manga)
    )
    vc.sheetPresentationController?.detents = [.medium(), .large()]
    vc.sheetPresentationController?.prefersGrabberVisible = true
    present(vc, animated: true)
}
```

### View model

```swift
@Observable
final class WordLookupViewModel {
    let surfaceForm: String
    let lemma: String
    let language: String
    let mangaId: String
    let sourceId: String

    var translation: WordTranslation?  // nil while loading
    var isInVocab: Bool
    var familiarity: Int16
    var isDone: Bool
    var loadError: TranslationError?

    func loadTranslation() async { ... }
    func toggleVocab() async { ... }
    func setFamiliarity(_ level: Int16) async { ... }
    func markDone() async { ... }
    func requestSentenceTranslation() { ... }  // emits event, view dismisses
}
```

Initial state derives from `CoreDataManager.shared.getVocabularyEntry(language:lemma:)`. If non-nil, `isInVocab = true` and `familiarity` / `isDone` populate from `progress`.

### Lemma normalization

`lemma = surfaceForm.lowercased().trimmingCharacters(in: .whitespacesAndPunctuation)` matches Task 2's storage normalization. Use the same helper in a shared `LearnerStrings.normalizeLemma(_:)` utility.

### Layout

```
┌──────────────────────────────────┐
│         (grabber)                │
├──────────────────────────────────┤
│                                  │
│   📖   Buch                      │   <- surface form, large
│                                  │
│        buch (lemma)              │   <- only if different
│                                  │
│   ─────────────────────────────  │
│   book                           │   <- translation
│   noun · neuter                  │   <- POS, if available
│                                  │
│   "Sie liest ein Buch."          │   <- example, if available (markdown)
│                                  │
│   ─────────────────────────────  │
│   ● ○ ○ ○   Familiarity          │   <- 4 dots, current level filled
│                                  │
│   [ ✓ Add to vocab ]             │   <- or "In vocab" with check
│   [ ✓ Mark Done ]                │   <- only if in vocab and not done
│                                  │
│   [ Translate this sentence  →]  │
│                                  │
└──────────────────────────────────┘
```

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Presentation | `UIHostingController` + `sheetPresentationController` detents | Matches `ReaderViewController.openReaderSettings` pattern at line 502 |
| 2 | Subscription | Combine `AnyCancellable` in `ReaderViewController` | Default — simplest hook |
| 3 | View model | `@Observable` (Swift Observation) | Default — current Apple recommendation, iOS 17+ |
| 4 | Translation source | `TranslationServiceFactory.shared.current()` | Task 3 |
| 5 | Lemma normalization | Lowercase + trim whitespace + trim punctuation | Matches Task 2 |
| 6 | Familiarity UI | 4 dots (0–3) | Matches data model (3 levels + initial 0) |
| 7 | Done UX | Separate "Mark Done" button | Distinguishes "got it 3 times right" from "never want to see again" |
| 8 | Sentence translation hand-off | Emit `LearnerEvents.shared.sentenceTranslateRequested(...)`, dismiss sheet | Loose coupling with Task 7 |
| 9 | Markdown | Reuse `MarkdownView` from `ReaderPageView.swift:10` import | Default — already in project |
| 10 | Translation errors | Map `TranslationError` to `LEARNER_TRANSLATION_*` localized strings | Already added in Task 3 |
| 11 | Re-tap on same word | Cache hit returns immediately | Task 3 cache is keyed by input |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | `iOS/UI/Learner/WordLookupSheet.swift` | SwiftUI view |
| CREATE | `iOS/UI/Learner/WordLookupViewModel.swift` | `@Observable` view model |
| CREATE | `Shared/Learner/LearnerStrings.swift` | `normalizeLemma(_:)` helper, used here and in Tasks 2, 7, 8 |
| MODIFY | `iOS/UI/Reader/ReaderViewController.swift` | Subscribe to `LearnerEvents.shared.wordTapped` in `viewDidLoad` (and unsubscribe in `viewWillDisappear`); present sheet on event |
| MODIFY | `Shared/Localization/en.lproj/Localizable.strings` | `LEARNER_WORD_LOOKUP_*`, `LEARNER_ADD_TO_VOCAB`, `LEARNER_IN_VOCAB`, `LEARNER_MARK_DONE`, `LEARNER_TRANSLATE_SENTENCE`, `LEARNER_FAMILIARITY` |
| CREATE | `AidokuTests/WordLookupViewModelTests.swift` | View model loads, toggles, persists |
| MODIFY | `Aidoku.xcodeproj/project.pbxproj` | Add files |

## Implementation Steps

- [ ] **Step 1: Implement `LearnerStrings.normalizeLemma`**
  - **What:** One-line helper used by Tasks 2, 6, 7, 8.
  - **Files:** `LearnerStrings.swift`
  - **Verify by:** Test: `"Buch."` → `"buch"`, `"Buch,"` → `"buch"`, `"  Buch  "` → `"buch"`.

- [ ] **Step 2: Implement `WordLookupViewModel`**
  - **What:** All methods listed in Approach. Constructor reads vocab state via `CoreDataManager.shared.getVocabularyEntry`. `loadTranslation` calls `TranslationServiceFactory.shared.current().translateWord(lemma, ...)`. State mutations call corresponding `CoreDataManager` methods on a background context.
  - **Files:** `WordLookupViewModel.swift`
  - **Depends on:** Step 1
  - **Verify by:** Test in Step 6.

- [ ] **Step 3: Implement `WordLookupSheet` SwiftUI view**
  - **What:** The layout in Approach. `.task { await viewModel.loadTranslation() }` on appear. Loading state = `ProgressView`. Error state = localized message. POS / example fields hidden when nil.
  - **Files:** `WordLookupSheet.swift`
  - **Depends on:** Step 2
  - **Verify by:** Compile; preview renders three states (loading, loaded, error).

- [ ] **Step 4: Add localization strings**
  - **Files:** `Localizable.strings`
  - **Verify by:** All keys referenced in `WordLookupSheet.swift` exist in strings file.

- [ ] **Step 5: Subscribe in `ReaderViewController`**
  - **What:** `viewDidLoad` adds the Combine subscription; `viewWillDisappear` cancels it. `presentWordLookup(_:)` builds the host controller and presents.
  - **Files:** `iOS/UI/Reader/ReaderViewController.swift`
  - **Depends on:** Step 3, Task 5
  - **Verify by:** Manual smoke test — tap a word in Learner mode, sheet appears.

- [ ] **Step 6: Tests**
  - **What:** `AidokuTests/WordLookupViewModelTests.swift`:
    1. `loadTranslation_setsTranslationOnSuccess` (with stub `TranslationService`).
    2. `loadTranslation_setsErrorOnFailure`.
    3. `toggleVocab_addsEntry_thenRemovesEntry` (in-memory CoreData).
    4. `setFamiliarity_persists` and triggers `vocabChanged` event.
    5. `requestSentenceTranslation_emitsEvent`.
  - **Files:** `WordLookupViewModelTests.swift`
  - **Depends on:** Steps 1–5
  - **Verify by:** `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/WordLookupViewModelTests` passes.

## Testing Strategy

- File: `AidokuTests/WordLookupViewModelTests.swift`.
- Stub `TranslationService`, in-memory `CoreDataManager`.
- Manual smoke: tap word, verify sheet UX matches the layout sketch.
- Run command: `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/WordLookupViewModelTests`.

## Risks

- **Most complex part:** Re-entrancy when the user taps a second word while the sheet is presenting. Apple's `UIViewController.present` rejects nested presents. Mitigation: in `ReaderViewController.presentWordLookup`, check `presentedViewController != nil`; if a sheet is already up, dismiss it first then re-present after the dismiss animation completes (single-trampoline pattern).
- **Most-likely-wrong assumption:** That `@Observable` (Swift Observation) plays cleanly with view-controller-presented sheets. It does, but the host controller's lifetime needs care — the view model must be retained as long as the sheet is presented. Mitigation: the view model is stored as a property on the SwiftUI view; the `UIHostingController` retains the view; lifecycle is correct.
- **Edge case:** A long German compound noun ("Bibliothekswissenschaft") may produce one box covering the whole word but the user wants per-component translation. MVP doesn't decompose. Note in the sheet: tapping the box translates the whole compound. Acceptable.
