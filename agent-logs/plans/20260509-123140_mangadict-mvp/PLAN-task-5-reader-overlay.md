---
task: 5
task_name: "reader-overlay"
status: completed
created: 2026-05-09
steps_total: 9
steps_completed: 9
estimated_files: 11
parallelizable_with: null
depends_on: [1, 4]
---

# Task 5 — Reader Learner Mode + OCR Overlay

## Goal

Add a per-manga "Learner mode" toggle to the reader, run OCR on each visible page when on, render an invisible tappable layer over recognized words, render familiarity badges over vocab-list words, and emit a `wordTapped(...)` signal that downstream UI tasks (6, 7) consume.

## Acceptance Criteria

- [ ] A "Learner" section is added to `ReaderSettingsView` with: a per-manga toggle `Learner Mode` (key `Learner.enabled.<mangaId>`), OCR languages multi-select (default `["de-DE"]`, key `Learner.ocrLanguages`), and a "Pause Live Text while Learner Mode is on" disclosure (`Reader.liveText` is auto-suppressed by Learner internally).
- [ ] When Learner mode is on for the current manga, `ReaderPagedViewController` calls a new `LearnerOverlayCoordinator.activatePage(_, image:, in:)` once the displayed image is ready and once again when the page becomes visible (covering both first-load and swipe-back cases).
- [ ] `LearnerOverlayCoordinator` runs OCR via `OCRService` (Task 4) and adds an overlay `UIView` as a subview of the existing `ZoomableScrollView`'s content (sibling of `ReaderPageView`, scaled with zoom). The overlay contains transparent `UIControl` regions per word.
- [ ] Tapping a word region triggers `LearnerEvents.shared.wordTapped(WordTapEvent)` (a Combine publisher / async stream). Other UI surfaces (Task 6) subscribe.
- [ ] Single-tap on a word does NOT trigger Aidoku's existing chrome-toggle gesture (verified by `require(toFail:)` chains).
- [ ] Words present in the user's vocabulary list show a familiarity badge: a small colored dot on the bottom-right corner of the word's bounding rect, color-coded by level (0 = grey, 1 = yellow, 2 = orange, 3 = green; "done" = solid green with checkmark).
- [ ] When Learner mode is off, no OCR runs; no overlay is added; reader behaves exactly as before.
- [ ] Switching Learner mode on/off mid-chapter immediately updates the visible page (turn on → OCR runs; turn off → overlay disappears).
- [ ] When Learner mode turns on for a page, the existing `Reader.liveText` interaction is removed for that page until Learner mode turns off (avoids competing tap layers).
- [ ] Webtoon mode is unaffected: the toggle is greyed out (with explanatory text) when reader mode != paged.

## What This Is Not

- No word lookup UI — Task 6 owns the bottom sheet.
- No sentence translation UI — Task 7 owns the long-press / button + sheet.
- No vocab list or flashcards UI — Task 8.
- No persistent OCR cache — Task 4's in-memory cache is sufficient.
- No webtoon mode support.

## Approach

### Component map

```
ReaderViewController                          (existing — adds Learner button to chrome)
  └─ Reader (ReaderPagedViewController)       (existing — emits page-changed)
       └─ ReaderPageViewController            (existing — owns one page)
            └─ ZoomableScrollView             (existing — UIScrollView)
                 └─ contentView (UIView)      (existing — wraps ReaderPageView)
                      ├─ ReaderPageView       (existing — UIImageView container)
                      └─ LearnerOverlayView   (NEW — sibling, full-bounds match)
```

`LearnerOverlayView` matches `ReaderPageView.imageView`'s frame so it scales naturally with zoom. We add it via constraints to the `ReaderPageView`'s `imageView`, which is the actual rendered image content.

### Coordinator

```swift
@MainActor
final class LearnerOverlayCoordinator {
    static let shared = LearnerOverlayCoordinator()
    private let ocr: OCRService = VisionOCRService()
    private var pageStates: [PageKey: PageState] = [:]
    private var liveTextSavedState: [PageKey: Bool] = [:]

    func activatePage(mangaId: String, sourceId: String, chapterId: String, pageIndex: Int,
                      image: UIImage, in container: ReaderPageView) async
    func deactivatePage(_ container: ReaderPageView)
    func setEnabled(_ enabled: Bool, for mangaId: String)  // mid-session toggle
}
```

`PageKey` = `(sourceId, mangaId, chapterId, pageIndex)`. `PageState` holds the current `LearnerOverlayView` reference so `deactivatePage` can remove it cleanly.

### Tap handling

Each word region is a `UIControl` subview of `LearnerOverlayView`. We override `hitTest(_:with:)` so taps on regions are claimed by `LearnerOverlayView`, while taps on empty space pass through to `ZoomableScrollView` (chrome toggle still works on bubble-empty space).

Aidoku's existing chrome-toggle tap (`barToggleTapGesture` in `ReaderViewController`) uses `require(toFail: doubleTapGesture)`. Our word tap is a `UIControl` action, not a gesture recognizer, so it doesn't conflict directly — but we need to make the `barToggleTapGesture` `require(toFail:)` Learner's word tap, which we do by exposing a single shared `UITapGestureRecognizer` on `LearnerOverlayView` that the existing controller can `require(toFail:)`.

Simpler alternative: each word region intercepts the tap via `UIControl.touchUpInside`; this naturally consumes the touch before chrome-toggle gets a chance because the region is in the touch hit-test path. The chrome-toggle gesture only fires if no UIControl claims the touch. Use this simpler approach.

### Familiarity badges

`LearnerOverlayView.update(with: OCRResult, vocabIndex: VocabIndex)` walks each word box, looks up `vocabIndex[normalize(text)]` for the word's lemma, and if found, draws a small `CAShapeLayer` circle at the bottom-right corner of the box.

`VocabIndex` is a tiny in-memory map `[(language, lemma) → FamiliarityLevel]` rebuilt on:
- `LearnerEvents.shared.vocabChanged.send()` (fired by Task 6 add/remove)
- View did appear

Colors:
- 0 (no progress): `.systemGray.withAlphaComponent(0.6)`
- 1: `.systemYellow`
- 2: `.systemOrange`
- 3: `.systemGreen`
- done: `.systemGreen` with `checkmark` symbol overlay

### Hook into `ReaderPageView`

Two points (the only edits needed in existing reader code):

1. `ReaderPageView.swift:117` (after `imageView.image = image; fixImageSize()`), call:
   ```swift
   LearnerOverlayCoordinator.shared.imageDidLoad(image, on: self)
   ```
2. The same call in the URL-load completion path around `ReaderPageView.swift:229` (`imageView.image = response.image`).

The coordinator decides if Learner mode is on for the current manga (by reading `Learner.enabled.\(mangaId)`) and, if so, attaches the overlay. When off, the call is a no-op.

### Page-change hook

`ReaderPagedViewController.swift:892-909` — the `pageViewController(_:didFinishAnimating:...)` delegate. Add one line:

```swift
LearnerOverlayCoordinator.shared.pageDidBecomeVisible(controller: currentPageVC)
```

This re-runs `imageDidLoad` if the cached image is already there but the overlay was deactivated (e.g. user toggled Learner off and back on while on this page).

### Settings UI

Add a section to `ReaderSettingsView.swift`:

```swift
Section(header: Text(NSLocalizedString("LEARNER_MODE"))) {
    SettingView(
        setting: .init(
            key: "Learner.enabled.\(mangaId)",
            title: NSLocalizedString("LEARNER_MODE_ENABLE"),
            value: .toggle(.init())
        )
    )
    if learnerModeOn {
        SettingView(
            setting: .init(
                key: "Learner.ocrLanguages",
                title: NSLocalizedString("LEARNER_OCR_LANGUAGES"),
                value: .multiSelect(.init(values: ["de-DE", "en-US", "ja-JP", "fr-FR", "es-ES"]))
            )
        )
    }
}
```

### Toolbar button

Optionally add a small button to the reader top chrome (`iOS/UI/Reader/ReaderToolbarView.swift:11-100`) that toggles `Learner.enabled.<mangaId>` directly without opening settings. Phase B step.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Reader mode supported | Paged only | PRD scope |
| 2 | Per-manga toggle | Yes, key `Learner.enabled.<mangaId>` | Matches `Reader.readingMode.<mangaId>` pattern (`ReaderSettingsView.swift:34`) |
| 3 | Default OCR language | `de-DE` | Vision doc |
| 4 | Overlay parent | Sibling subview to `imageView` inside `ReaderPageView`'s bounds | Default — scales with zoom for free |
| 5 | Tap handling | Per-word `UIControl` regions; rely on hit-test precedence over chrome-toggle | Default — simpler than gesture recognizer chains |
| 6 | Live Text coexistence | Suppress `Reader.liveText` interaction on a per-page basis when Learner is active | Default — avoids competing tap layers |
| 7 | OCR trigger | On image-loaded AND on page-became-visible | Default — covers both first-load and swipe-back |
| 8 | Familiarity badge style | Small colored dot, 4-color scale + done checkmark | Default — minimal visual noise |
| 9 | Vocab index refresh | On `vocabChanged` event from Task 6 + on view appear | Default — eventual consistency, cheap |
| 10 | Toolbar button | Add a small "AB" symbol button next to settings gear | Default — discoverability |
| 11 | Mid-session toggle | Live update overlay on next page render; current page re-renders immediately | Default — feels responsive |
| 12 | Webtoon mode | Toggle disabled with explanatory text | Default — avoid misleading users |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | `Shared/Learner/Reader/LearnerOverlayCoordinator.swift` | `@MainActor` class managing per-page overlays |
| CREATE | `Shared/Learner/Reader/LearnerOverlayView.swift` | `UIView` subclass; renders word regions + badges |
| CREATE | `Shared/Learner/Reader/LearnerEvents.swift` | `@MainActor` event hub: `wordTapped`, `sentenceTranslateRequested`, `vocabChanged` (Combine `PassthroughSubject` or `AsyncStream`) |
| CREATE | `Shared/Learner/Reader/VocabIndex.swift` | In-memory `[(language, lemma) → FamiliarityLevel]` cache rebuilt on `vocabChanged` |
| MODIFY | `iOS/UI/Reader/Page/ReaderPageView.swift` | Two new one-line calls into `LearnerOverlayCoordinator.shared.imageDidLoad(...)` after `imageView.image =` assignments at lines 115 and 229 |
| MODIFY | `iOS/UI/Reader/Readers/Paged/ReaderPagedViewController.swift` | One new call to `LearnerOverlayCoordinator.shared.pageDidBecomeVisible(...)` inside the existing `pageViewController(_:didFinishAnimating:...)` delegate around line 892 |
| MODIFY | `iOS/UI/Reader/ReaderViewController.swift` | Add Learner toggle button to top chrome (next to settings gear at the area around line 502) |
| MODIFY | `iOS/New/Views/Reader/ReaderSettingsView.swift` | Add Learner section with `Learner.enabled.\(mangaId)` toggle + `Learner.ocrLanguages` multi-select; greyed out when reader mode != paged |
| MODIFY | `Shared/Localization/en.lproj/Localizable.strings` | Add `LEARNER_MODE`, `LEARNER_MODE_ENABLE`, `LEARNER_OCR_LANGUAGES`, `LEARNER_PAGED_ONLY_NOTICE`, etc. |
| CREATE | `AidokuTests/LearnerOverlayTests.swift` | Coordinator wiring, vocab-index refresh, tap event |
| MODIFY | `Aidoku.xcodeproj/project.pbxproj` | Add files to targets |

## Implementation Steps

### Phase A — Settings + module scaffolding

- [x] **Step 1: Add localization strings**
  - **Files:** `Localizable.strings`
  - **Verify by:** `grep -c "^\"LEARNER_" Shared/Localization/en.lproj/Localizable.strings` increases by ≥ 5.

- [x] **Step 2: Add Learner section to `ReaderSettingsView.swift`**
  - **What:** New `Section` with the toggle + OCR-language multi-select. Greyed when `readingModeKey` value isn't `.rtl/.ltr/.vertical` (paged-style modes). Use the existing `SettingView(setting:)` pattern at `ReaderSettingsView.swift:251-280` (upscaling toggle).
  - **Files:** `iOS/New/Views/Reader/ReaderSettingsView.swift`
  - **Depends on:** Step 1
  - **Verify by:** Open settings, see the Learner section appear; toggle persists per-manga (kill app, reopen, value retained).

- [x] **Step 3: Add `LearnerEvents.swift` and `VocabIndex.swift`**
  - **What:** Event hub with three publishers; vocab-index rebuilds from `CoreDataManager.shared.getAllVocabulary()` on subscription and on `vocabChanged`.
  - **Files:** `LearnerEvents.swift`, `VocabIndex.swift`
  - **Depends on:** Task 2 (data model)
  - **Verify by:** Compile passes; no consumers yet.

### Phase B — Overlay rendering

- [x] **Step 4: Implement `LearnerOverlayView`**
  - **What:** `UIView` subclass with `update(image: UIImage, words: [OCRWordBox], vocab: VocabIndex)`. Removes existing region subviews; for each word box, transforms normalized rect to view coords (Y-flip), creates a `UIControl` with `addTarget(self, action: #selector(wordTapped:), for: .touchUpInside)`, sets its `accessibilityLabel = word.text`. After regions, draws badge `CAShapeLayer`s for words found in `vocab`.
  - **Files:** `LearnerOverlayView.swift`
  - **Depends on:** Step 3, Task 4 (`OCRWordBox` type)
  - **Verify by:** Unit test: mock OCR result with 3 words, vocab map with 1 of them; assert 3 controls + 1 badge layer.

- [x] **Step 5: Implement `LearnerOverlayCoordinator`**
  - **What:** `@MainActor` class. `imageDidLoad(_ image: UIImage, on container: ReaderPageView)`:
    1. Resolve `(sourceId, mangaId, chapterId, pageIndex)` from `container`'s associated metadata (added via `container.objc_setAssociatedObject` from the page-view-controller, since `ReaderPageView` doesn't currently know its identity — alternative: pass identity through a new param to the new method, simpler).
    2. Check `Learner.enabled.\(mangaId)`; if off, deactivate and return.
    3. Suppress Live Text on the page (call `container.imageView.removeInteraction(...)` for any `ImageAnalysisInteraction`).
    4. Call `OCRService.recognize(image:languages:)`.
    5. Add (or reuse) a `LearnerOverlayView` constrained to `container.imageView`'s bounds.
    6. Call `overlay.update(image:words:vocab:)`.
  - **Files:** `LearnerOverlayCoordinator.swift`
  - **Depends on:** Steps 3, 4, Task 4
  - **Verify by:** Manual smoke test on simulator with a real chapter (described in step 9).

### Phase C — Reader integration

- [x] **Step 6: Hook into `ReaderPageView`**
  - **What:** Add a stored property `var learnerContext: LearnerPageContext?` to `ReaderPageView`. After `imageView.image = image` on lines 115 and 229, call:
    ```swift
    if let ctx = learnerContext, let img = imageView.image {
        Task { await LearnerOverlayCoordinator.shared.imageDidLoad(img, context: ctx, container: self) }
    }
    ```
    `LearnerPageContext` is a small struct `(sourceId, mangaId, chapterId, pageIndex)`. The page-view-controller sets it before calling `setPage(...)`.
  - **Files:** `iOS/UI/Reader/Page/ReaderPageView.swift`
  - **Depends on:** Step 5
  - **Verify by:** Compile + manual smoke test.

- [x] **Step 7: Wire context-setting in `ReaderPageViewController`**
  - **What:** `ReaderPageViewController` (`/iOS/UI/Reader/Readers/Paged/ReaderPageViewController.swift`) constructs the `LearnerPageContext` from its existing `chapter`/`manga`/`pageIndex` properties and assigns to `pageView.learnerContext` before calling `setPage`.
  - **Files:** `iOS/UI/Reader/Readers/Paged/ReaderPageViewController.swift`
  - **Depends on:** Step 6
  - **Verify by:** Manual smoke test in step 9.

- [x] **Step 8: Hook page-change**
  - **What:** In `ReaderPagedViewController.swift` inside `pageViewController(_:didFinishAnimating:...)` around line 909 (after `delegate?.setCurrentPage(...)`), call `LearnerOverlayCoordinator.shared.pageDidBecomeVisible(...)` with the new visible page's context. This refreshes the overlay if vocab/familiarity changed since last render.
  - **Files:** `iOS/UI/Reader/Readers/Paged/ReaderPagedViewController.swift`
  - **Depends on:** Step 7
  - **Verify by:** Manual smoke test.

### Phase D — Tests + smoke

- [x] **Step 9: Tests + manual smoke**
  - **What:** `AidokuTests/LearnerOverlayTests.swift`:
    1. Coordinator no-op when toggle off.
    2. Coordinator calls OCR + adds overlay when toggle on.
    3. `LearnerOverlayView.update(...)` builds correct number of regions + badges.
    4. `vocabChanged` event triggers `VocabIndex.rebuild()`.
  - **Manual smoke:** Open a chapter with Learner mode on. Verify yellow word boxes appear after a brief delay (≤2s). Tap a word, verify console logs `wordTapped(text:)`. Toggle Learner off mid-page, overlay disappears. Add a word to vocab manually via test seed, verify badge appears on next page.
  - **Files:** `LearnerOverlayTests.swift`
  - **Depends on:** Steps 1–8
  - **Verify by:** Tests pass; manual checklist done.

## Testing Strategy

- File: `AidokuTests/LearnerOverlayTests.swift`.
- Stubs for `OCRService` and `CoreDataManager` (in-memory).
- Manual smoke test on real device or simulator with a German manga chapter — final gate.
- Run command: `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/LearnerOverlayTests -destination 'platform=iOS Simulator,name=iPhone 16'`.

## Risks

- **Most complex part:** Coordinate transform from Vision's normalized bottom-left coords to `LearnerOverlayView`'s top-left UIKit coords, while remaining correct under arbitrary zoom and content-offset changes from `ZoomableScrollView`. Mitigation: pin the overlay to `imageView` (not `ZoomableScrollView`), so zoom transforms apply to overlay automatically; only Y-flip is needed.
- **Most-likely-wrong assumption:** That suppressing `Reader.liveText` per-page is harmless. If a user has Live Text habitually enabled and Learner mode confuses them by removing it, the UX is non-obvious. Mitigation: a small disclosure under the toggle ("Live Text is paused while Learner Mode is on"). Already in localization strings.
- **Edge case:** Chapter prefetch — Aidoku may render a hidden "next page" view before the user swipes. If our overlay attaches to a hidden page, OCR runs needlessly. Mitigation: defer the OCR call until `pageDidBecomeVisible` confirms visibility, OR check `container.window != nil` before invoking OCR.
