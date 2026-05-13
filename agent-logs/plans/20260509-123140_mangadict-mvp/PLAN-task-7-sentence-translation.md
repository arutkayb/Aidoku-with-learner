---
task: 7
task_name: "sentence-translation"
status: planned
created: 2026-05-09
steps_total: 5
steps_completed: 0
estimated_files: 8
parallelizable_with: [6]
depends_on: [2, 3, 5]
---

# Task 7 — Sentence Translation Flow

## Goal

When the user long-presses a region of the page or taps a "Translate page" button, send the page's OCR fragments to the translation service, group them into sentences via Foundation Models, and show each sentence + its translation + a CEFR-simplified rephrase in a panel.

## Acceptance Criteria

- [ ] `SentenceTranslationSheet` SwiftUI view exists at `iOS/UI/Learner/SentenceTranslationSheet.swift`.
- [ ] Two entry points trigger the sheet:
  1. A "Translate page" button in the Learner toolbar group (added to the same chrome row as the Learner toggle from Task 5).
  2. A long-press (≥0.6 s) anywhere on the overlay (when not on a word region) — recognized by a new `UILongPressGestureRecognizer` on `LearnerOverlayView` that doesn't conflict with chrome-toggle (use `require(toFail:)` chain).
- [ ] `LearnerEvents.shared.sentenceTranslateRequested(for: WordTapEvent?)` event fires from Task 6's "Translate this sentence" button; `ReaderViewController` subscribes and presents the same sheet pre-scrolled to the sentence containing the tapped word.
- [ ] Sheet contents:
  - Header: "<chapter title> · page <N>".
  - For each sentence group returned by `groupFragmentsIntoSentences`: two stacked rows — first row shows the source-language sentence, second row shows the translated sentence; a small chevron expands a "Simplified (A2)" row underneath.
  - Loading skeleton while sentences are still being fetched.
  - Error state if Foundation Models is unavailable (with retry button).
- [ ] Word-tap inside a sentence in the sheet behaves the same as tapping in the reader (opens `WordLookupSheet` from Task 6) — consistent UX.
- [ ] Sentence rendering uses Apple's standard text styles (Title3 for source, Body for translation, Caption for simplified).
- [ ] Tests cover: grouping invariant (combined fragments cover all input fragments), end-to-end view-model state machine (loading → loaded → simplified-on-demand), simplification fires only when a row is expanded (lazy fetch).

## What This Is Not

- No bubble-region detection — vision doc explicitly defers algorithmic bubble grouping to the LLM. We pass all detected fragments and let the LLM group.
- No persistent sentence cache. Re-opening the sheet re-runs grouping.
- No editing of grouped sentences.
- No save-sentence-to-vocab feature (vocab is word-level only).
- No multi-language UI; all sentences in one language per page.

## Approach

### Trigger surfaces

| Trigger | Source |
|---------|--------|
| "Translate page" button | New `UIBarButtonItem` (or chrome subview) added in Task 5's toolbar work — Task 7 just wires the button action |
| Long-press on overlay | `UILongPressGestureRecognizer` on `LearnerOverlayView`, ignored if a word region claims the touch |
| "Translate this sentence" from word sheet | Task 6 emits event; Task 7 subscribes |

All three call into a single coordinator method:

```swift
@MainActor
final class SentenceTranslationCoordinator {
    func presentSheet(
        for context: LearnerPageContext,
        ocrResult: OCRResult,
        focusOnLemma: String? = nil
    )
}
```

`focusOnLemma` lets the third trigger scroll to the sentence containing the tapped word.

### View model

```swift
@Observable
final class SentenceTranslationViewModel {
    let context: LearnerPageContext
    let ocrResult: OCRResult
    let focusLemma: String?

    var sentences: [SentenceVM] = []  // populated after grouping
    var isLoading = true
    var loadError: TranslationError?

    func load() async { ... }                      // grouping + parallel translation
    func simplify(sentenceId: UUID) async { ... }  // lazy on expand
}

struct SentenceVM: Identifiable {
    let id = UUID()
    let source: String
    var translation: String?  // populated as it arrives
    var simplified: String?
    var simplifyExpanded = false
}
```

### Pipeline inside `load()`

```
1. Convert ocrResult.lines into [TextFragment(index, text)].
2. await groupFragmentsIntoSentences(fragments, language: lang)  → [SentenceGroup]
3. For each group, kick off translateSentence(combinedText, ...) concurrently via TaskGroup.
4. As translations arrive, update sentences[i].translation and re-render.
```

`TaskGroup<(Int, String?)>` so we can populate translations out of order without re-renders blocking.

### Long-press

In Task 5, `LearnerOverlayView` already has `UIControl` regions for words. Add a `UILongPressGestureRecognizer` to the overlay's empty space. Use `gestureRecognizer(_:shouldReceive:)` to refuse the long-press if `view.hitTest(point, with: event)` is a word region (let the word-tap take precedence on `touchUpInside`).

### Settings

| UserDefaults key | Default | Purpose |
|---|---|---|
| `Learner.simplifyOnTranslate` | `true` | Show simplified row by default expanded |
| `Learner.simplificationLevel` | `"A2"` | Used by `simplifyToCEFR(_:level:)` |

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Trigger entry points | Three: button, long-press, "translate sentence" from word sheet | Vision doc mentions both long-press and a button |
| 2 | Long-press duration | 0.6 s | iOS default; adjustable later |
| 3 | Sentence grouping | LLM-only (Foundation Models), no algorithmic fallback | Vision doc |
| 4 | Translation fan-out | Parallel via `TaskGroup` | Default — minimizes wall-clock latency |
| 5 | Simplification | Lazy on row expand | Default — saves model calls; user explicitly opts in |
| 6 | Sentence view rendering | Plain text, system fonts | Default — matches Aidoku's minimal aesthetic |
| 7 | Word tap inside sheet | Reuse Task 6 `WordLookupSheet` flow | Consistent UX; no duplicate code |
| 8 | Persistent sentence cache | No | Default — Task 3's per-method cache covers re-opening within a session |
| 9 | Sheet detents | Medium + Large | Matches Task 6 |
| 10 | Re-fetch on retry | Full pipeline (group + translate) | Default — simplest |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | `iOS/UI/Learner/SentenceTranslationSheet.swift` | SwiftUI view |
| CREATE | `iOS/UI/Learner/SentenceTranslationViewModel.swift` | `@Observable` view model |
| CREATE | `Shared/Learner/Reader/SentenceTranslationCoordinator.swift` | `@MainActor` orchestrator subscribing to button + long-press + word-sheet events |
| MODIFY | `Shared/Learner/Reader/LearnerOverlayView.swift` | Add `UILongPressGestureRecognizer`; emit `sentenceTranslateRequested` on long-press |
| MODIFY | `iOS/UI/Reader/ReaderViewController.swift` | Subscribe to `sentenceTranslateRequested`; present sheet |
| MODIFY | `Shared/Localization/en.lproj/Localizable.strings` | `LEARNER_TRANSLATE_PAGE`, `LEARNER_SIMPLIFIED_LABEL`, `LEARNER_SENTENCE_LOAD_ERROR`, `LEARNER_RETRY` |
| CREATE | `AidokuTests/SentenceTranslationViewModelTests.swift` | Grouping invariant, lazy simplify, error path |
| MODIFY | `Aidoku.xcodeproj/project.pbxproj` | Add files |

## Implementation Steps

- [ ] **Step 1: Implement `SentenceTranslationViewModel`**
  - **What:** All methods in Approach. Use `TaskGroup` for parallel translation. `simplify(sentenceId:)` is the only call that fires `simplifyToCEFR`.
  - **Files:** `SentenceTranslationViewModel.swift`
  - **Depends on:** Tasks 3, 4
  - **Verify by:** Tests in Step 5.

- [ ] **Step 2: Implement `SentenceTranslationSheet` SwiftUI view**
  - **What:** `ScrollView` with `LazyVStack` of sentence rows; each row is a `DisclosureGroup` for the simplified version; tapping a word in the source/translation strings opens `WordLookupSheet`. `.task { await viewModel.load() }` on appear.
  - **Files:** `SentenceTranslationSheet.swift`
  - **Depends on:** Step 1
  - **Verify by:** Preview renders all three states.

- [ ] **Step 3: Implement `SentenceTranslationCoordinator`**
  - **What:** Subscribes to `LearnerEvents.shared.sentenceTranslateRequested` in `ReaderViewController.viewDidLoad`. Resolves the current page's `OCRResult` from `LearnerOverlayCoordinator`'s state. Builds the view model, presents the sheet via `UIHostingController`.
  - **Files:** `SentenceTranslationCoordinator.swift`, `ReaderViewController.swift`
  - **Depends on:** Step 2
  - **Verify by:** Manual smoke test in Step 5.

- [ ] **Step 4: Add long-press to overlay**
  - **What:** In `LearnerOverlayView`, attach `UILongPressGestureRecognizer(target:action:)` with `minimumPressDuration = 0.6`. In the action, fetch the current page context and emit `LearnerEvents.shared.sentenceTranslateRequested(for: nil)`. Word tap takes precedence by virtue of the per-region `UIControl.touchUpInside` consuming the touch sequence first.
  - **Files:** `LearnerOverlayView.swift`
  - **Depends on:** Step 3
  - **Verify by:** Manual smoke test.

- [ ] **Step 5: Tests + smoke**
  - **What:** `AidokuTests/SentenceTranslationViewModelTests.swift`:
    1. `load_groupsAndTranslates`: stub returns 3 groups; assert `sentences.count == 3` and translations populate.
    2. `load_propagatesError` on `groupFragmentsIntoSentences` failure.
    3. `simplify_lazyFire`: simplify is NOT called in `load()`; only when `simplify(id:)` is called.
    4. `simplify_failureKeepsRowExpanded` with error message.
  - **Manual smoke:** On a German page, tap "Translate page". Sheet appears. 3-5 sentences listed. Tap a sentence's chevron → simplified version appears. Tap a word in the sentence → `WordLookupSheet` appears.
  - **Files:** `SentenceTranslationViewModelTests.swift`
  - **Depends on:** Steps 1–4
  - **Verify by:** Tests pass; smoke checklist done.

## Testing Strategy

- File: `AidokuTests/SentenceTranslationViewModelTests.swift`.
- Stub `TranslationService` records calls to verify lazy simplify.
- Manual smoke on a real chapter — final gate.
- Run command: `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/SentenceTranslationViewModelTests`.

## Risks

- **Most complex part:** The grouping prompt's reliability. Foundation Models may return groups whose `combinedText` doesn't actually correspond to the source fragments (hallucination, dropped fragments, reordering). Mitigation: the view model validates that every input fragment index appears exactly once across groups; if validation fails, fall back to a degenerate "one fragment = one sentence" grouping (each line is its own sentence) and log the failure for tuning.
- **Most-likely-wrong assumption:** That long-press on overlay-empty-space gives a clean enough trigger. If users accidentally long-press while trying to read, the sheet pops up annoyingly. Mitigation: the explicit "Translate page" button is the primary trigger; the long-press is a power-user shortcut. Disable it via a setting if it proves too noisy.
- **Edge case:** A page with no detected text (cover page, full-bleed art) — `OCRResult.lines.isEmpty`. Sheet should show a clear "No text detected on this page" message instead of an infinite spinner.
