---
task: 3
task_name: "live-text-coexistence"
status: planned
created: 2026-05-12
steps_total: 4
steps_completed: 0
estimated_files: 3
parallelizable_with: [4, 5]
depends_on: [2]
---

## Goal

Allow VisionKit Live Text (`ImageAnalysisInteraction`) to remain active on a page while the Learner overlay is also active. Word taps go to Learner; Live Text's selection / lookup gestures still work elsewhere on the page.

## Acceptance Criteria

- [ ] With Learner ON for a manga and the global "Live Text" reader setting ON, the Live Text button (the small SF Symbol that VisionKit places) appears on the page when zoom == 1.
- [ ] Tapping a Learner-detected word region opens WordLookupSheet (not Live Text selection).
- [ ] Long-pressing an area that has Live-Text-recognized text BUT no Learner word region triggers Live Text's selection (the iOS system text selection callout).
- [ ] No regressions in the existing `setLiveTextHidden(_:)` behavior driven by `onZoomScaleChanged` / `barsHidden` (zoomed-in state still hides the LT button).
- [ ] Deactivating Learner mid-session (via Task 1) does NOT remove Live Text — they're independent now.

## What This Is Not

- No change to `Reader.liveText` setting or its location. Users still toggle Live Text globally via the existing reader setting.
- No new explicit Learner-vs-LiveText switcher button. Coexistence is automatic.
- No change to how Live Text analysis is queued / cancelled (`startLiveTextAnalysis` / `cancelLiveTextAnalysis` in `ReaderPageView.swift:527-558`).

## Approach

- Today, `LearnerOverlayCoordinator.suppressLiveText(on:for:key:)` (`LearnerOverlayCoordinator.swift:188-203`) removes every `ImageAnalysisInteraction` from the imageView when Learner activates, and stashes them in `PageState.detachedLiveTextInteractions`. `restoreLiveText(on:for:)` adds them back when deactivating. The comment on lines 185-187 says this is to prevent the LT long-press from stealing the overlay's long-press touches.
- With Task 2's gesture-delegate fix, word-tap conflicts are resolved at the recognizer level. The long-press in `LearnerOverlayView.swift:226-233` already has a delegate that refuses the long-press if the touch lands on a word region, so the two long-press recognizers can coexist: when the user long-presses on Learner-empty space, Learner's recognizer rejects it (line 230 returns false because the touch isn't inside a word subview), and the LT interaction's recognizer (a deeper UIInteraction) gets the touch.
- Wait — re-reading line 226-233 more carefully: the existing delegate rejects the long-press **only** when the touch is inside a word region (returns false). On empty space the long-press IS accepted (returns true). That means Learner's long-press currently always wins on empty space. With Live Text re-attached, both want empty-space long-press. Resolution: change Learner's long-press behavior so it activates only when the touch is on a Learner word region (i.e., invert the predicate). But then the only sentence-translation trigger is the WordLookupSheet's "Translate sentence" button — which is exactly what Task 6 (Q: "Tap a word, then sentence sheet…") chose. So we can simply **remove** the long-press recognizer from `LearnerOverlayView` entirely. Sentence translation is now driven from the word-lookup sheet only.

  Result: no Learner gesture competes with Live Text. `suppressLiveText` is no longer needed.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Live Text + Learner coexistence | Both active simultaneously, Learner wins on word taps via gesture delegate (Task 2) | User answered Q5 |
| 2 | Remove the `suppressLiveText`/`restoreLiveText` mechanism | Yes | No longer needed once Learner's long-press is removed and Task 2's gesture-delegate handles word-tap conflicts |
| 3 | Remove `LearnerOverlayView`'s long-press recognizer | Yes | Sentence translation is driven from WordLookupSheet's button (per Task 6 user answer Q6). Removing the recognizer is what makes coexistence safe. |
| 4 | Keep `PageState.detachedLiveTextInteractions` field | No, remove | Dead state once `suppressLiveText` is gone |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | Shared/Learner/Reader/LearnerOverlayCoordinator.swift | Delete `suppressLiveText(on:for:)` and `restoreLiveText(on:for:)` methods (lines 188-212); remove call sites (line 60 `suppressLiveText(...)`, lines 134, 153 `restoreLiveText(...)`); delete `detachedLiveTextInteractions` field from `PageState` (line 36); simplify `imageDidLoad` and `deactivate` accordingly. |
| MODIFY | Shared/Learner/Reader/LearnerOverlayView.swift | Remove the `UILongPressGestureRecognizer` setup (lines 33, 39-43); remove `handleLongPress(_:)` (lines 149-154); remove the `UIGestureRecognizerDelegate` extension (lines 222-234) — it only existed to gate the now-removed long-press. |
| MODIFY | AidokuTests/LearnerOverlayTests.swift | Update or remove tests that reference `suppressLiveText`, `detachedLiveTextInteractions`, or the long-press path; verify `@Suite struct LearnerCoordinatorTests` still covers deactivate/reactivate |

Note: `iOS/UI/Reader/ReaderViewController.swift` is intentionally NOT in this table. The Combine subscription `sentenceTranslateSubscription = LearnerEvents.shared.sentenceTranslateRequested` (lines 322-324) still fires from WordLookupSheet's "Translate sentence" button and requires no change. Verification in Step 1 confirms only WordLookupViewModel/ReaderViewController remain as sender/subscriber.

## Implementation Steps

- [ ] **Step 1: Remove Learner's long-press recognizer**
  - **What:** delete the `longPressRecognizer` property, the recognizer setup in `init(frame:)`, the `handleLongPress(_:)` method, and the `UIGestureRecognizerDelegate` extension in `LearnerOverlayView.swift`. The only `LearnerEvents.shared.sentenceTranslateRequested` sender will be `WordLookupViewModel.requestSentenceTranslation(event:)` at `WordLookupViewModel.swift:154-156`.
  - **Files:** `Shared/Learner/Reader/LearnerOverlayView.swift`
  - **Verify by:** `grep -rn sentenceTranslateRequested Shared iOS` shows only the `WordLookupViewModel` sender and the `ReaderViewController` subscriber.

- [ ] **Step 2: Remove suppressLiveText machinery**
  - **What:** in `LearnerOverlayCoordinator.swift`, delete `suppressLiveText` (188-203), `restoreLiveText` (205-212), the call at line 60, the field `detachedLiveTextInteractions` at line 36 of `PageState`, and the references at lines 99, 104, 134, 153. Also delete the `import VisionKit` if no longer used (line 12). The `deactivate(for:container:)` method becomes simpler.
  - **Files:** `Shared/Learner/Reader/LearnerOverlayCoordinator.swift`
  - **Verify by:** `swift build`. Unit tests `LearnerCoordinatorTests` still pass.

- [ ] **Step 3: Manual smoke on device**
  - **What:** with global LT on and Learner on, open a manga: see the LT button. Tap a Learner word → WordLookupSheet. Long-press an LT-detectable area outside any Learner word → iOS text selection callout. Zoom in → LT button hides (existing behavior via `setLiveTextHidden`). Toggle Learner off per-manga (Task 1) → LT stays on.
  - **Files:** none
  - **Verify by:** behaviors match Acceptance Criteria.

- [ ] **Step 4: Update or remove related tests**
  - **What:** in `AidokuTests/`, search for tests referencing `suppressLiveText`, `detachedLiveTextInteractions`, or the long-press path inside `AidokuTests/LearnerOverlayTests.swift`. Either delete or rewrite. Verify the simpler `@Suite struct LearnerCoordinatorTests` (line 141 of that file) still covers deactivate/reactivate.
  - **Files:** `AidokuTests/LearnerOverlayTests.swift`
  - **Verify by:** `xcodebuild test -only-testing:AidokuTests/LearnerCoordinatorTests` passes (suite name targets the same Swift Testing suite).

## Testing Strategy

- Existing `LearnerCoordinatorTests` (graph community 100) — adapt if any test asserts on `detachedLiveTextInteractions`.
- No automated test for Live Text presence (VisionKit interactions are device-only).
- Manual end-to-end on iPhone hardware (simulators may not run LT analysis on all images).

## Risks

- **Most complex:** the long-press conflict cited in the original suppress-LT comment. If, after deleting Learner's long-press, the LT long-press still gets occasionally swallowed by some other recognizer (e.g., the bar-toggle delegate from Task 2 returning false too aggressively), users will report LT broken. Mitigation: only return false for the delegate predicate when the touch view is a `WordRegionControl` (NOT when it's `LearnerOverlayView` itself). LT's hit-test lives at `imageView` level, which is the overlay's superview, so the bar-toggle predicate must allow touches on the bare overlay through.
- **Assumption most likely wrong:** that removing the Learner long-press isn't a regression for existing users who rely on long-press for sentence translation. Mitigation: the WordLookupSheet's "Translate sentence" button (line 145-153) covers the same intent; document in the release note.
- **Easy-to-miss edge case:** the global `Reader.liveText` setting is OFF — then nothing about coexistence applies. Verify the simplified coordinator still handles `imageDidLoad` correctly when the imageView has zero `ImageAnalysisInteraction`s.
