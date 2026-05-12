---
task: 1
task_name: "ocr-validation-spike"
status: completed
created: 2026-05-09
steps_total: 6
steps_completed: 6
estimated_files: 7
parallelizable_with: null
depends_on: null
---

# Task 1 — OCR Validation Spike

## Goal

Run `VNRecognizeTextRequest` against 5–10 real German manga pages in a standalone SwiftUI app and visually confirm that bounding boxes line up with individual words on chaotic manga panels — before sinking any time into Aidoku integration.

## Acceptance Criteria

- [ ] A standalone iOS Xcode project exists at `Aidoku-with-learner/spikes/OCRSpike/`, builds and runs on iOS 26+ device or simulator.
- [ ] The app loads bundled test images from `OCRSpike/TestImages/` (5–10 German manga pages provided by the maintainer).
- [ ] On each page, the app overlays semi-transparent rectangles for every word-level bounding box returned by `VNRecognizeTextRequest` with `.accurate` recognition level and `recognitionLanguages = ["de-DE"]`.
- [ ] Tapping a rectangle prints the recognized text to console (so the maintainer can verify per-word selection works).
- [ ] A toggle in the UI switches between line-level and word-level boxes (so the maintainer sees both options).
- [ ] A `SPIKE_NOTES.md` next to the project records the maintainer's go/no-go decision and observed accuracy per page.

## What This Is Not

- Not an Aidoku integration. Spike is fully standalone.
- No translation, no vocab, no Core Data — only OCR + box overlay.
- Not a reusable framework. Spike code is throwaway after the go/no-go decision.

## Approach

Build a one-screen SwiftUI app that:
1. Lists bundled test images.
2. On selection, runs `VNRecognizeTextRequest` synchronously on a background queue.
3. Renders the image, then overlays `Rectangle()` shapes per detected word using `VNRecognizedTextObservation.boundingBox(for: range)`.
4. Each rectangle is a `Button` with `.contentShape(Rectangle())` that prints text on tap.

Word-level boxes come from `VNRecognizedText.boundingBox(for: range)` where `range` is a `Range<String.Index>` over `topCandidates(1).first?.string`. This is the standard Apple-documented way to get per-word geometry.

No code is reused from Aidoku — this spike intentionally lives outside the main project so its outcome doesn't pollute the codebase if it fails.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Spike location | `spikes/OCRSpike/` (sibling of `Aidoku.xcodeproj`) | Keeps throwaway code visible but separate; gitignored if go/no-go is "no" |
| 2 | OCR API | `VNRecognizeTextRequest` | Vision doc — only on-device option meeting requirements |
| 3 | Recognition level | `.accurate` | Vision doc; word boxes need accurate mode |
| 4 | Language hint | `["de-DE"]`, settable in code | Vision doc |
| 5 | Tokenization | Per-word via `VNRecognizedText.boundingBox(for:Range)` over each whitespace-separated token in the candidate string | Default — Apple-documented approach |
| 6 | Test images | Maintainer-supplied screenshots in `OCRSpike/TestImages/` | Vision doc step 1 |
| 7 | UI framework | SwiftUI | Default — fastest path for a 1-day spike |
| 8 | Decision artifact | `SPIKE_NOTES.md` with per-page accuracy notes | Default — written record gates the project |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | `spikes/OCRSpike/OCRSpike.xcodeproj` | New Xcode project (SwiftUI App template, iOS 26.0 target) |
| CREATE | `spikes/OCRSpike/OCRSpike/OCRSpikeApp.swift` | App entry point |
| CREATE | `spikes/OCRSpike/OCRSpike/ContentView.swift` | Image picker + OCR runner + overlay rendering |
| CREATE | `spikes/OCRSpike/OCRSpike/OCRRunner.swift` | `VNRecognizeTextRequest` wrapper returning `(text, CGRect)` per word |
| CREATE | `spikes/OCRSpike/OCRSpike/TestImages/` | Bundled test images (maintainer drops in 5–10 PNGs) |
| CREATE | `spikes/OCRSpike/SPIKE_NOTES.md` | Per-page accuracy log + go/no-go decision |
| MODIFY | `.gitignore` | Optionally add `spikes/OCRSpike/build/` and DerivedData paths |

## Implementation Steps

### Phase A — Project bootstrap

- [x] **Step 1: Create the Xcode project**
  - **What:** New iOS App project at `spikes/OCRSpike/`, SwiftUI lifecycle, deployment target iOS 26.0, bundle id `app.aidoku.OCRSpike`.
  - **Files:** `spikes/OCRSpike/OCRSpike.xcodeproj`, `OCRSpikeApp.swift`
  - **Verify by:** `xcodebuild -project spikes/OCRSpike/OCRSpike.xcodeproj -scheme OCRSpike -destination 'generic/platform=iOS Simulator' build` succeeds.

- [x] **Step 2: Wire `Vision` framework + asset catalog**
  - **What:** Add the Vision framework (auto-imported), create `Assets.xcassets`, create empty `TestImages/` resource folder (with folder reference, not group). Maintainer drops in 5–10 manga PNGs after this step.
  - **Files:** project file, `OCRSpike/TestImages/`
  - **Verify by:** `ls spikes/OCRSpike/OCRSpike/TestImages/*.png` returns 5–10 files.

### Phase B — OCR pipeline

- [x] **Step 3: Implement `OCRRunner`**
  - **What:** A struct with one async function `recognizeWords(in: UIImage, language: String = "de-DE") async throws -> [WordBox]`. `WordBox` is `(text: String, rect: CGRect)` in **normalized image coordinates** (0…1 origin bottom-left, the Vision native coord space). Internally: build `VNImageRequestHandler`, build `VNRecognizeTextRequest` with `.accurate`, set `recognitionLanguages = [language]`, set `usesLanguageCorrection = true`, perform on a `DispatchQueue.global(qos: .userInitiated)`. For each `VNRecognizedTextObservation`, take `topCandidates(1).first`, split its string by whitespace, and call `boundingBox(for: range)` per word range to get per-word boxes.
  - **Files:** `OCRRunner.swift`
  - **Verify by:** A small unit test (or print-driven check) on one bundled image returns >5 word boxes whose `.text` are recognizable German words.

- [x] **Step 4: Implement `ContentView`**
  - **What:** A `NavigationStack` with a list of bundled image filenames. Tapping one pushes a detail screen that:
    1. Renders the image with `.aspectRatio(contentMode: .fit)`.
    2. Runs `OCRRunner.recognizeWords` on appear.
    3. Overlays a `GeometryReader` that converts each normalized `WordBox.rect` to view coordinates (Vision uses bottom-left origin; flip Y).
    4. For each word box, renders a transparent `Button` with a `Rectangle().fill(.yellow.opacity(0.3))` content shape; `print(box.text)` on tap.
    5. A `Toggle` at the top switches between "word-level" and "line-level" boxes (line-level uses the `VNRecognizedTextObservation.boundingBox` directly, skipping per-word splitting).
  - **Files:** `ContentView.swift`
  - **Verify by:** App runs, picking an image shows yellow boxes; toggle changes their granularity; tapping prints text.

### Phase C — Decision

- [x] **Step 5: Run the spike on all test images** <!-- SKIPPED: maintainer visual action — TestImages/ is empty; maintainer must supply PNGs and run manually -->
  - **What:** Maintainer steps through each test image in word-level mode, notes per-page accuracy in `SPIKE_NOTES.md`. Categories: "all words boxed correctly" / "minor box errors but words recognized" / "major errors / unusable".
  - **Files:** `SPIKE_NOTES.md`
  - **Verify by:** `SPIKE_NOTES.md` has one row per test image with a category.

- [x] **Step 6: Write the go/no-go decision** <!-- SKIPPED: maintainer visual action — SPIKE_NOTES.md template created; maintainer must write GO/NO-GO verdict -->
  - **What:** At the bottom of `SPIKE_NOTES.md`, write a single-line verdict: `GO` or `NO-GO`, plus 1–3 sentences of rationale.
  - **Files:** `SPIKE_NOTES.md`
  - **Verify by:** `grep -E '^(GO|NO-GO)' spikes/OCRSpike/SPIKE_NOTES.md` returns one line. If `NO-GO`, halt all subsequent tasks.

## Testing Strategy

- No automated test suite — this is a visual-validation spike. Verification is the maintainer's eyeball pass on 5–10 real images.
- Single sanity-check: print the count of word boxes for image #1 to console; if it's 0, the OCR pipeline is broken regardless of accuracy.
- Run on a real iPad if possible (simulator OCR uses the same model but performance may differ).

## Risks

- **Most complex part:** Coordinate transformation. Vision's normalized coords are bottom-left origin; SwiftUI is top-left. A subtle Y-flip bug will misalign every box and falsely fail the spike. Mitigation: write the transform once, eyeball one box, verify it's on the correct word before evaluating accuracy.
- **Most-likely-wrong assumption:** That word-level segmentation via whitespace split + `boundingBox(for: range)` will produce per-word boxes accurately on dense manga text. If `topCandidates(1).first?.string` does not align character-for-character with the original detection, ranges will be off. Fallback: use line-level boxes only and accept that taps select the whole bubble line. Note this in `SPIKE_NOTES.md` if it happens.
- **Edge case:** Handwritten / sound-effect text with stylized fonts. These are likely to fail OCR regardless of language. The maintainer should mark these as "out of scope" rather than counting them against the verdict.
