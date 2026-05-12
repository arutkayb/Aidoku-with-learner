---
task: 2
task_name: "zoom-and-tap-conflict"
status: completed
created: 2026-05-12
steps_total: 6
steps_completed: 6
estimated_files: 5
parallelizable_with: [4]
depends_on: []
---

## Goal

Make OCR word taps continue to work after pinch/double-tap zoom, and stop the reader chrome (top/bottom bar) from toggling when the user taps a word region.

## Acceptance Criteria

- [ ] After pinching to any zoom scale > 1 (or double-tap zoom), tapping a yellow word region opens the WordLookupSheet and the word region's frame matches the highlighted word on screen pixel-for-pixel.
- [ ] After zooming back out (scale == 1), word taps still work.
- [ ] Tapping a word region does NOT show/hide the top navigation bar (`navigationController.navigationBar.alpha` is unchanged across the tap).
- [ ] Tapping an empty area of the page (no word region) DOES toggle the bar as before (preserves existing reader UX).
- [ ] Existing `WordLookupViewModelTests`, `LearnerCoordinatorTests` continue to pass.

## What This Is Not

- No change to which words are detected. Pure overlay-frame + gesture-handling fix.
- No change to the `ZoomableScrollView` zoom math (scale limits, double-tap behavior) other than adding one callback.

## Approach

- Two independent root causes, fixed together because the affected files overlap:

  **Cause A (zoom):** `LearnerOverlayView` is added as a subview of `ReaderPageView.imageView` with edge constraints (`LearnerOverlayCoordinator.swift:83-89`). Word region frames are computed from `displayedImageRect(in: size)` (`LearnerOverlayView.swift:188-218`) only inside `rebuild()`. `rebuild()` is invoked from `layoutSubviews` only when `bounds.size` changes (line 81). Pinch-zoom applies a `CGAffineTransform` to the scroll view's content; the overlay's `bounds.size` is unchanged in points, so no rebuild fires, but `displayedImageRect` was computed against the un-transformed image rect. After zoom, hit-test regions remain in the right place for the user's eye in 90% of cases — but `ZoomableScrollView.centerView()` (line 67-86) sets `zoomView.frame = frameToCenter` on every zoom change, which DOES alter the pageView frame and consequently can re-layout the imageView and overlay. Empirically taps stop working; the safe fix is to actively rebuild the overlay whenever the zoom scale changes.

  **Fix A:** add an `onZoomScaleChanged` consumer that calls `overlay.setNeedsRebuild()`. Pipe it via `ReaderPageViewController.swift:112-114` (already wires `onZoomScaleChanged` to `pageView.setLiveTextHidden`) — extend the closure to also call `LearnerOverlayCoordinator.shared.zoomChanged(for: pageView.learnerContext, container: pageView)`. The coordinator looks up the overlay for that context and calls `overlay.rebuildNow()` (renamed from private `rebuild()` exposed via an internal `setNeedsRebuild()`).

  **Cause B (gesture):** `ReaderViewController.swift:215` adds `barToggleTapGesture` to the top-level `view`. The recognizer doesn't have a delegate, so it fires for every tap that reaches the view — even when a `WordRegionControl` (UIControl subclass at `LearnerOverlayView.swift:239`) consumed `touchUpInside`. UIControl tap events and UITapGestureRecognizer are not mutually exclusive in UIKit; you must implement `UIGestureRecognizerDelegate` to block.

  **Fix B:** make `ReaderViewController` conform to `UIGestureRecognizerDelegate` and set itself as the delegate of both `fakeZoomTapGesture` and `barToggleTapGesture` (lines 87-98). Implement `gestureRecognizer(_:shouldReceive:)` to return `false` when the touched view is a `WordRegionControl` or descendant of `LearnerOverlayView`. Reuse the `walk view hierarchy` pattern from `LearnerOverlayView.swift:226-233` (existing gesture delegate inside the overlay for long-press exclusion).

- One small refactor: move `WordRegionControl` from `private final class` (file-scoped) to `internal final class` so `ReaderViewController` can do an `is WordRegionControl` type check. Alternative without the visibility bump: check `view.isDescendant(of: someOverlay)` — but the controller doesn't have a strong reference to overlays. Going with visibility bump.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Trigger overlay rebuild on zoom | Yes, via `ZoomableScrollView.onZoomScaleChanged` already-existing hook | Existing hook at `ReaderPageViewController.swift:112-114` already fires reliably on every scale change |
| 2 | Coordinator exposes zoom hook | Add `func zoomChanged(for:container:)` to `LearnerOverlayCoordinator` | Coordinator already owns the per-page `PageState` map and is the documented entry point for reader-side changes |
| 3 | Where to block bar-toggle | `UIGestureRecognizerDelegate.gestureRecognizer(_:shouldReceive:)` on `ReaderViewController` | UIKit's intended hook for gesture-vs-UIControl conflicts |
| 4 | How to identify a word touch | `touch.view is WordRegionControl` OR `touch.view?.isDescendant(of: LearnerOverlayView)` | Type-check is cheap and unambiguous; `WordRegionControl` is bumped to `internal` |
| 5 | WordRegionControl visibility | Bump from `private` (file scope) to `internal` | Required for cross-file `is` check |
| 6 | Apply fix to all gestures or just bar-toggle | Both `barToggleTapGesture` AND `fakeZoomTapGesture` get the delegate | A word tap should also not register as the failure-of-double-tap that allows the bar tap through — explicit is safer |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | Shared/Learner/Reader/LearnerOverlayView.swift | Make `WordRegionControl` `internal`; add `func setNeedsRebuild()` that calls private `rebuild()` |
| MODIFY | Shared/Learner/Reader/LearnerOverlayCoordinator.swift | Add `func zoomChanged(for context: LearnerPageContext, container: ReaderPageView)` that looks up overlay and calls `setNeedsRebuild()` |
| MODIFY | iOS/UI/Reader/Readers/Paged/ReaderPageViewController.swift | Line 112-114: extend `onZoomScaleChanged` closure to also call `LearnerOverlayCoordinator.shared.zoomChanged(for: ctx, container: pageView)` when `learnerContext` exists |
| MODIFY | iOS/UI/Reader/ReaderViewController.swift | Conform to `UIGestureRecognizerDelegate`; set delegate on `fakeZoomTapGesture` (line 87-91) and `barToggleTapGesture` (line 93-98); implement `gestureRecognizer(_:shouldReceive:)` returning false for `WordRegionControl` touches |
| CREATE | AidokuTests/ReaderGestureDelegateTests.swift | New unit test asserting the gesture delegate predicate returns false for a touch on a WordRegionControl under a LearnerOverlayView |

## Implementation Steps

- [x] **Step 1: Expose overlay rebuild and word-region type**
  - **What:** in `LearnerOverlayView.swift`, change `private final class WordRegionControl: UIControl` → `final class WordRegionControl: UIControl`. Add `func setNeedsRebuild() { rebuild() }` on `LearnerOverlayView` (public-by-default; matches `update(words:...)` visibility).
  - **Files:** `Shared/Learner/Reader/LearnerOverlayView.swift`
  - **Verify by:** `swift build` succeeds with no new warnings about access level.

- [x] **Step 2: Add coordinator zoom hook**
  - **What:** add `@MainActor func zoomChanged(for context: LearnerPageContext, container: ReaderPageView)` to `LearnerOverlayCoordinator`. Looks up `pageStates[PageKey(context)]?.overlay` and calls `setNeedsRebuild()` on it.
  - **Files:** `Shared/Learner/Reader/LearnerOverlayCoordinator.swift`
  - **Verify by:** unit-test (or quick xcodebuild) that compilation succeeds.

- [x] **Step 3: Wire zoom callback in page view controller**
  - **What:** in `ReaderPageViewController.swift:112-114`, replace the existing one-liner with a multi-statement closure that calls `setLiveTextHidden(...)` AND, when `pageView.learnerContext` is non-nil, calls `LearnerOverlayCoordinator.shared.zoomChanged(for: ctx, container: pageView)`.
  - **Files:** `iOS/UI/Reader/Readers/Paged/ReaderPageViewController.swift`
  - **Verify by:** pinch-zoom a paged manga page with learner active; word regions visually align with their words at any zoom; tap fires WordLookupSheet.

- [x] **Step 4: Make ReaderViewController a UIGestureRecognizerDelegate**
  - **What:** add `extension ReaderViewController: UIGestureRecognizerDelegate { func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { /* false if touch.view is WordRegionControl or descendant of LearnerOverlayView */ } }`. Set `barToggleTapGesture.delegate = self` and `fakeZoomTapGesture.delegate = self` inside the lazy initializers (lines 87-98) — or in `viewDidLoad` after they're added to the view (lines 213-215).
  - **Files:** `iOS/UI/Reader/ReaderViewController.swift`
  - **Verify by:** tap a word on a learner-enabled manga; navigation bar alpha stays at its current value (use breakpoint or print). Tap empty page area; bar toggles.

- [x] **Step 5: Manual end-to-end smoke**
  - **What:** install on device, open a paged German manga with learner on, verify (a) pre-zoom tap, (b) pinch-zoom 2x, (c) double-tap zoom, (d) zoom back out — every word tap opens WordLookupSheet without flashing the bar.
  - **Files:** none
  - **Verify by:** behavior matches Acceptance Criteria 1–4.

- [x] **Step 6: Unit test for the gesture delegate predicate**
  - **What:** in `AidokuTests/`, add a small test that constructs a `WordRegionControl` instance, places it in a UIView hierarchy under a `LearnerOverlayView`, and asserts that `ReaderViewController`'s gesture delegate predicate returns `false` for a touch whose `view` is that control. Use the same Swift Testing `@Test` pattern.
  - **Files:** create `AidokuTests/ReaderGestureDelegateTests.swift`
  - **Verify by:** `xcodebuild test -only-testing:AidokuTests/ReaderGestureDelegateTests` passes.

## Testing Strategy

- New unit test file `AidokuTests/ReaderGestureDelegateTests.swift` covering the delegate predicate.
- Manual on-device verification for the zoom rebuild (no headless way to fire UIScrollView zoom in unit tests reliably).
- Existing `LearnerCoordinatorTests` should continue to pass with the added `zoomChanged` method (no behavior change when no overlay registered).

## Risks

- **Most complex:** detecting "touch on a word region" reliably. UIKit's `touch.view` is the deepest hit-tested subview; `WordRegionControl` is a leaf, so `touch.view is WordRegionControl` should be sufficient — but if a child view (badge `CAShapeLayer`) is somehow on top, the cast may miss. Mitigation: also walk up `touch.view?.superview` chain looking for a `LearnerOverlayView` ancestor, return false if found.
- **Assumption most likely wrong:** that `onZoomScaleChanged` fires on every zoom transform update (it currently fires inside `scrollViewDidZoom`, which UIScrollView calls during gesture too — verified). If it doesn't fire on the trailing edge after gesture ends, the overlay may be a frame off. Mitigation: also rebuild in `scrollViewDidEndZooming` (would require exposing another callback).
- **Easy-to-miss edge case:** the double-page reader (`ReaderDoublePageViewController`). Its zoom view is shared by two `pageView`s; check whether `learnerContext` is set on both and rebuild both overlays.
