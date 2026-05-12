---
task: 6
task_name: "sentence-focus-and-reocr"
status: planned
created: 2026-05-12
steps_total: 5
steps_completed: 0
estimated_files: 6
parallelizable_with: [4, 5]
depends_on: [2]
---

## Goal

Make sentence translation usable: tapping a word and pressing "Translate sentence" opens the sentence sheet scrolled to and highlighting the sentence that contains that word. Add a "Re-OCR this page" affordance in the reader menu for cases where some bubbles weren't recognized.

## Acceptance Criteria

- [ ] In the reader, tap a word inside a multi-line speech bubble → WordLookupSheet → tap "Translate sentence" → the sentence sheet opens and the visible scroll position is the sentence containing that lemma; that sentence's source-text row has a visible highlight (e.g., background tint).
- [ ] When the LLM-driven grouping in `SentenceTranslationViewModel.loadSourceSentences` fails or returns invalid indices, the fallback uses **OCR-line bubble adjacency** (group consecutive non-empty lines whose bounding boxes intersect vertically by ≥ 50% of average line height) instead of one-per-line. Verified by a unit test.
- [ ] A "Re-OCR this page" menu item is reachable from the reader (e.g., in the reader's top-bar menu or via long-press on the page indicator) when Learner is active on the current page. Tapping it clears the page's OCR cache and re-runs OCR.
- [ ] After a re-OCR, the on-page overlay updates without leaving the page.
- [ ] Existing `SentenceTranslationViewModelTests` continue to pass; one new test covers the bubble-adjacency fallback grouping.

## What This Is Not

- No long-press-on-overlay path (removed in Task 3). The only sentence entry is the word-lookup-sheet button.
- No standalone "Translate page" UI (covered indirectly when a sentence sheet is opened).
- No change to the LLM grouping prompt itself (`FoundationModelsTranslationService.swift:144-158`). Only the fallback changes.
- No bubble-bounding-box overlay (rejected in Q6 in favor of the simpler "tap-word-then-jump" approach).

## Approach

- **Focus + highlight:** the existing `presentSentenceTranslation(focusEvent:)` in `ReaderViewController.swift:541-582` already passes `focusLemma` to `SentenceTranslationSheet`. The sheet must scroll/highlight. Find the row whose `source` text (case-insensitively, diacritic-insensitively) contains the focus lemma; scroll to it via SwiftUI `ScrollViewReader.scrollTo(_:)`; apply a background tint that fades after ~1.5 seconds.
- **Better fallback grouping:** in `SentenceTranslationViewModel.loadSourceSentences`, the current fallback (lines 108-114) produces one-fragment-per-line on LLM failure. Replace with a heuristic that groups OCR lines belonging to the same speech bubble:
  - Build `OCRLineBox` array from `ocrResult.lines` (preserves bounding boxes).
  - Compute average line height `h_avg = mean(line.boundingBox.height)`.
  - For each consecutive pair of lines, decide "same bubble" if the vertical center distance ≤ `1.5 * h_avg` AND horizontal overlap ≥ `0.5 * min(width_a, width_b)` AND no large vertical gap (≥ `2 * h_avg`).
  - Concatenate text within each group with a single space.
  - Wrap into `SentenceGroup(fragmentIndices:combinedText:)`.
- **Re-OCR menu item:** add a method on `LearnerOverlayCoordinator` `func reOCR(for context: LearnerPageContext, container: ReaderPageView)` that calls `cache.invalidate(...)` on the page's PNG and then re-runs `imageDidLoad(...)`. The `OCRResultCache` (`Shared/Learner/OCR/OCRResultCache.swift`) needs an `invalidate(imageData:languages:)` method (likely missing — add it). Wire a button into `ReaderViewController`'s existing toolbar/menu setup; the existing menu construction lives near `openReaderSettings` (line 584). If no menu exists, add a single button visible only when `LearnerGate.isEnabled(...)` is true for the current manga.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Sentence selection mechanism | Tap word → sentence sheet scrolls to + highlights that sentence | User answered Q6 |
| 2 | Re-OCR affordance | Reader menu button "Re-OCR this page" visible when Learner active | User answered Q7 (first item) |
| 3 | Fallback grouping algorithm | Bubble-adjacency heuristic (vertical center + horizontal overlap thresholds) | LLM-failure fallback today is one-per-line which is unusable; geometric heuristic uses data Vision already provides |
| 4 | Scrolling library | SwiftUI `ScrollViewReader` + `.scrollTo(id, anchor: .center)` | The sheet is SwiftUI; no UIKit indirection needed |
| 5 | Highlight visual | Background `Color.accentColor.opacity(0.15)` fading to clear over 1.5 s via `.animation(.easeOut(duration: 1.5))` | Subtle, matches platform |
| 6 | Sentence row identifier for ScrollViewReader | The existing `SentenceVM.id: UUID` (already on the type) | No new fields |
| 7 | Re-OCR menu placement | Reader top-bar overflow menu (gear button area near `openReaderSettings`) | Reuses existing toolbar; doesn't add new top-level chrome |
| 8 | Diacritic-insensitive lemma match for focus | Yes, using `String.folding(options: .diacriticInsensitive, locale: .current)` for the search comparison only | Task 7 may later make lemma stripping diacritic-aware; the focus match should not break either way |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | iOS/UI/Learner/SentenceTranslationSheet.swift | Wrap the sentence list in `ScrollViewReader`; on appear, if `viewModel.focusLemma != nil`, find the matching `SentenceVM`, call `.scrollTo(matchId, anchor: .center)`, and animate a background highlight on that row that fades to clear. |
| MODIFY | iOS/UI/Learner/SentenceTranslationViewModel.swift | Replace lines 108-114 (one-per-line fallback) with a call to a new `static func bubbleGroupedFallback(from lines: [OCRLineBox]) -> [SentenceGroup]`. Implement the heuristic in the same file. Make the function public-internal so tests can invoke it directly. |
| MODIFY | Shared/Learner/Reader/LearnerOverlayCoordinator.swift | Add `@MainActor func reOCR(for context: LearnerPageContext, container: ReaderPageView)`: invalidate cache entry, set the page's cached `lastOCRResult = nil`, call `imageDidLoad(...)` with the current image. |
| MODIFY | Shared/Learner/OCR/OCRResultCache.swift | Add `func invalidate(imageData: Data, languages: [String])` symmetric with `put` / `get`. |
| MODIFY | iOS/UI/Reader/ReaderViewController.swift | Locate the existing reader menu/toolbar (around `openReaderSettings` at line 584 or in `setupToolbar`-like methods); insert a menu item "LEARNER_RE_OCR_PAGE" gated by `LearnerGate.isEnabled(mangaId: manga.key)`. On tap, resolve the current `LearnerPageContext`, current `ReaderPageView`, and call `LearnerOverlayCoordinator.shared.reOCR(for:container:)`. |
| MODIFY | AidokuTests/SentenceTranslationViewModelTests.swift | Add test for `bubbleGroupedFallback` with three synthetic `OCRLineBox`es forming two visually-distinct bubbles → expect two groups. |

## Implementation Steps

- [ ] **Step 1: Bubble-adjacency fallback grouping**
  - **What:** add `static func bubbleGroupedFallback(from lines: [OCRLineBox]) -> [SentenceGroup]` to `SentenceTranslationViewModel.swift`. Replace the one-per-line block at lines 108-114 with a call to this function (using the line objects, not just the fragments) when `groupingIsValid == false`. To keep the call site clean, extend the existing local helper that builds `fragments` so it captures the original `OCRLineBox` array. Add the unit test (three synthetic `OCRLineBox`es forming two visually-distinct bubbles → expect two groups) to `AidokuTests/SentenceTranslationViewModelTests.swift`.
  - **Files:** `iOS/UI/Learner/SentenceTranslationViewModel.swift`, `AidokuTests/SentenceTranslationViewModelTests.swift`
  - **Verify by:** `xcodebuild test -only-testing:AidokuTests/SentenceTranslationViewModelTests` passes.

- [ ] **Step 2: ScrollViewReader + highlight in sentence sheet**
  - **What:** wrap the existing list/scroll in `SentenceTranslationSheet.swift` with `ScrollViewReader { proxy in ... }`. In `.onAppear`, compute the first matching SentenceVM whose `source.folding(...).lowercased()` contains `viewModel.focusLemma?.folding(...).lowercased()`. Call `proxy.scrollTo(match.id, anchor: .center)` (animated) and set `@State var highlightedId: UUID?` to the match's id. Apply `.background(highlightedId == sentence.id ? Color.accentColor.opacity(0.15) : Color.clear)` with a 1.5 s animation back to clear.
  - **Files:** `iOS/UI/Learner/SentenceTranslationSheet.swift`
  - **Verify by:** open sentence translation for a focused word; verify the matching row is centered and tinted; tint fades.

- [ ] **Step 3: OCR cache invalidate API**
  - **What:** add the `invalidate(imageData:languages:)` method to `OCRResultCache.swift` mirroring the existing `put` keying logic.
  - **Files:** `Shared/Learner/OCR/OCRResultCache.swift`
  - **Verify by:** quick `@Test` in `AidokuTests/`: put → invalidate → get returns nil.

- [ ] **Step 4: Coordinator re-OCR entry point**
  - **What:** add `reOCR(for:container:)` to `LearnerOverlayCoordinator.swift`. Implementation: compute PNG data from `container.imageView.image`, call `cache.invalidate(...)`, clear `pageStates[key]?.lastOCRResult` to nil, then call `imageDidLoad(image, context:, container:)` to re-run. Existing overlay subview reuse path will replace the OCR result and refresh badges.
  - **Files:** `Shared/Learner/Reader/LearnerOverlayCoordinator.swift`
  - **Verify by:** manual smoke (Step 5).

- [ ] **Step 5: Reader menu button**
  - **What:** locate the reader's menu construction (search for `openReaderSettings`, `UIMenu`, or similar in `ReaderViewController.swift`). Add an entry titled by `NSLocalizedString("LEARNER_RE_OCR_PAGE")`. Gate visibility on `LearnerGate.isEnabled(mangaId: manga.key)`. On selection, resolve the current page's `ReaderPageView` via the existing visible-page accessor (search `currentPage`/`pageView` usages), build a `LearnerPageContext`, and call the coordinator.
  - **Files:** `iOS/UI/Reader/ReaderViewController.swift`
  - **Verify by:** open a manga where one bubble was untranslated → menu → Re-OCR → previously-missing overlay regions appear.

## Testing Strategy

- New unit test in `SentenceTranslationViewModelTests` for `bubbleGroupedFallback`:
  - Input: three `OCRLineBox`es. Lines 0 & 1 have vertically close, horizontally overlapping boxes (same bubble). Line 2 is far below with no horizontal overlap (different bubble).
  - Expected output: two groups, `[0,1]` and `[2]`.
- Existing test infra: see graph community 64 / `SpyTranslationService` for grouping-result manipulation.
- Manual on-device smoke for the highlight + re-OCR flows.

## Risks

- **Most complex:** the bubble-adjacency heuristic. Manga panel layouts vary wildly; the thresholds (`1.5 * h_avg`, `0.5 * min(width)`) will work for most German-translated manga (the user's use case) but may misgroup multi-column kanji panels. Mitigation: keep the thresholds as `static let`-style constants at the top of the function so they're easy to tune; ship with conservative values that err on the side of more groups (under-grouping is recoverable; over-grouping mixes unrelated speech).
- **Assumption most likely wrong:** that `ScrollViewReader.scrollTo` works inside a sheet with `.medium()` detent. SwiftUI sometimes ignores `scrollTo` when the scroll view hasn't laid out yet. Mitigation: trigger the scroll inside `.task` rather than `.onAppear`, and re-trigger on `sentences.count` change.
- **Easy-to-miss edge case:** a `focusLemma` that doesn't appear in any sentence's source text (e.g., user tapped a word whose surface form differs from any grouped fragment due to dedup). Then no highlight, no scroll — just show the sheet from the top. Test this path.
