---
task: 4
task_name: "ocr-service"
status: planned
created: 2026-05-09
steps_total: 5
steps_completed: 0
estimated_files: 6
parallelizable_with: [2, 3]
depends_on: [1]
---

# Task 4 — OCR Service

## Goal

Build a reusable, async OCR service that takes a `UIImage` and returns word-level + line-level bounding boxes in normalized image coordinates, with results cached by image hash so a re-visited page doesn't re-OCR.

## Acceptance Criteria

- [ ] `OCRService` protocol exists at `Shared/Learner/OCR/OCRService.swift` with one async method:
  - `recognize(image: UIImage, languages: [String]) async throws -> OCRResult`
- [ ] `OCRResult` is a `Sendable` value type with `[OCRWordBox]` and `[OCRLineBox]` arrays. Each box has `text: String`, `boundingBox: CGRect` (normalized 0…1, bottom-left origin matching Vision native), `confidence: Float`.
- [ ] `VisionOCRService` (default impl) uses `VNRecognizeTextRequest` with `.accurate` recognition level and the supplied language hint. Configurable via `Learner.ocrLanguages` UserDefault (defaults to `["de-DE"]`).
- [ ] Results are cached in-memory keyed by `(SHA256(image bytes), languages.joined("|"))` with capacity 32 entries (one chapter's worth). Cache is per-process.
- [ ] Per-word boxes are derived via `VNRecognizedText.boundingBox(for: range)` for each whitespace-separated token in the candidate string; if a token's range cannot be resolved (rare degenerate case), fall back to the line box for that word's index.
- [ ] Tests cover: same-image re-call hits cache (verified via call counter on a stub `VNRequestPerformer`), language change misses cache, an obviously-recognizable test image (a bundled fixture with simple printed text) produces ≥ 3 word boxes whose text matches expected words.
- [ ] No OCR runs on the main thread. Verified by the test harness asserting `Thread.isMainThread == false` inside the request callback.

## What This Is Not

- No persistent cache. Re-launching the app re-OCRs visited pages.
- No image preprocessing (cropping, despeckling, contrast normalization) beyond what Vision does internally. If the validation spike (Task 1) showed accuracy issues that preprocessing could fix, that's a v2 enhancement.
- No multi-language auto-detect. Caller passes the languages.
- No UI — this is a service layer only.
- No batch / page-prefetch API. One image per call.

## Approach

### API surface

```swift
public protocol OCRService: Sendable {
    func recognize(image: UIImage, languages: [String]) async throws -> OCRResult
}

public struct OCRResult: Sendable, Hashable {
    public let words: [OCRWordBox]
    public let lines: [OCRLineBox]
}

public struct OCRWordBox: Sendable, Hashable {
    public let text: String
    public let boundingBox: CGRect  // normalized, bottom-left origin
    public let confidence: Float
    public let lineIndex: Int       // points into OCRResult.lines
}

public struct OCRLineBox: Sendable, Hashable {
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float
}
```

### Implementation

`VisionOCRService.recognize` runs the request on a dedicated `DispatchQueue(label: "app.aidoku.learner.ocr", qos: .userInitiated)`. The async wrapper bridges via `withCheckedThrowingContinuation`.

Per-word boxes follow the spike-validated approach (Task 1):

```swift
let candidate = obs.topCandidates(1).first
let lineText = candidate?.string ?? ""
let words = lineText.split(separator: " ", omittingEmptySubsequences: true)
for token in words {
    if let range = lineText.range(of: token),
       let wordObs = try? candidate?.boundingBox(for: range) {
        boxes.append(OCRWordBox(text: String(token), boundingBox: wordObs.boundingBox, ...))
    }
}
```

### Cache

`NSCache<NSString, OCRResult>` is not Sendable-safe, so wrap result in a class box `final class _Box: NSObject { let value: OCRResult }`. Cache key is `"\(sha256)|\(langs)"`. Image bytes for hashing come from `image.pngData()` — modest cost compared to OCR itself.

If the user changes `Learner.ocrLanguages`, all cached results for the previous language are eventually evicted by LRU; we don't proactively flush.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Recognition level | `.accurate` | Vision doc; word-level segmentation needs accurate |
| 2 | Default language | `de-DE` | Vision doc |
| 3 | Language source | `Learner.ocrLanguages` UserDefault, defaults to `["de-DE"]` | Matches `Reader.*` UserDefault pattern |
| 4 | Coordinate space | Normalized (0…1), bottom-left origin (Vision native) | Default — pushes Y-flip to render layer where it's contextual |
| 5 | Cache type | `NSCache`-backed, in-memory, 32-entry LRU | Default — sized for one chapter |
| 6 | Cache key | `(SHA256(pngData), languages joined)` | Default — image-content-based, not URL-based, so cache survives source URL changes |
| 7 | Threading | Dedicated serial queue, async wrapper | Default — keeps reader main thread responsive |
| 8 | Error type | `OCRError` enum (`.imageUnsupported`, `.cancelled`, `.requestFailed(Error)`) | Default — explicit cases for UI mapping |
| 9 | Test fixture | Bundled `.png` with known German text, e.g. "Hallo Welt" | Default — small, deterministic |
| 10 | Image hashing cost | Acceptable; PNG encode is microseconds vs OCR seconds | Default — measured during spike |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | `Shared/Learner/OCR/OCRService.swift` | Protocol + value types |
| CREATE | `Shared/Learner/OCR/VisionOCRService.swift` | Concrete `VNRecognizeTextRequest` impl |
| CREATE | `Shared/Learner/OCR/OCRResultCache.swift` | NSCache wrapper with SHA256 keying |
| CREATE | `AidokuTests/OCRServiceTests.swift` | Caching, threading, recognition smoke test |
| CREATE | `AidokuTests/Fixtures/ocr-hallo-welt.png` | Bundled test image with known German text |
| MODIFY | `Aidoku.xcodeproj/project.pbxproj` | Add files to targets; add fixture to AidokuTests resources |

## Implementation Steps

- [ ] **Step 1: Define protocol + value types**
  - **What:** `OCRService.swift` with the protocol and `OCRResult`, `OCRWordBox`, `OCRLineBox`, `OCRError`. All `Sendable`.
  - **Files:** `OCRService.swift`
  - **Verify by:** Compile passes.

- [ ] **Step 2: Implement `OCRResultCache`**
  - **What:** Class wrapping `NSCache<NSString, _Box>`, with `func get(imageData: Data, languages: [String]) -> OCRResult?` and `func put(...)`. Use `CryptoKit.SHA256` for hashing.
  - **Files:** `OCRResultCache.swift`
  - **Verify by:** Test inserts and retrieves; hit count tracked in test.

- [ ] **Step 3: Implement `VisionOCRService`**
  - **What:** Concrete class. `recognize(image:languages:)` does:
    1. Compute cache key from `image.pngData()` + languages. Return cached if present.
    2. Build `VNImageRequestHandler(cgImage: image.cgImage!, orientation: .up)` (manga images are typically upright).
    3. Build `VNRecognizeTextRequest`: `recognitionLevel = .accurate`, `recognitionLanguages = languages`, `usesLanguageCorrection = true`.
    4. Bridge `request.results` → `OCRResult` using the per-word logic from Approach.
    5. Cache result, return.
  - **Files:** `VisionOCRService.swift`
  - **Depends on:** Steps 1, 2
  - **Verify by:** Smoke test in step 5.

- [ ] **Step 4: Add test fixture**
  - **What:** Drop `ocr-hallo-welt.png` (a 200×100 PNG with the rendered text "Hallo Welt") into `AidokuTests/Fixtures/`. Add to test target as bundle resource.
  - **Files:** Fixture PNG, `Aidoku.xcodeproj/project.pbxproj`
  - **Verify by:** Test loads bundle resource and produces non-empty bytes.

- [ ] **Step 5: Tests**
  - **What:** `AidokuTests/OCRServiceTests.swift`:
    1. `recognize_basicGerman_returnsKnownWords` — load fixture, `recognize(_, languages: ["de-DE"])`, assert `result.words.contains { $0.text == "Hallo" }` and `"Welt"`.
    2. `recognize_cachedResult_doesNotReinvoke` — recognize twice with same image and languages, second call short-circuits (use a counting test double over `VisionOCRService`).
    3. `recognize_languageChange_missesCache` — same image, different languages, second call DOES re-invoke.
    4. `recognize_offMainThread` — run inside `Task.detached`; inside a stubbed `request.completionHandler`, assert `Thread.isMainThread == false`.
  - **Files:** `OCRServiceTests.swift`
  - **Depends on:** Steps 3, 4
  - **Verify by:** `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/OCRServiceTests` passes.

## Testing Strategy

- File: `AidokuTests/OCRServiceTests.swift` (Swift Testing).
- Bundled small PNG fixture for deterministic OCR check.
- Cache tests use a wrapper that counts underlying calls; no real Vision invocation needed for those.
- Run command: `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/OCRServiceTests -destination 'platform=iOS Simulator,name=iPhone 16'`.

## Risks

- **Most complex part:** Per-word `boundingBox(for: range)` mapping when the recognized string contains compound German words (e.g. "Bibliothekswissenschaft"). Whitespace-split alone is correct — German doesn't space-separate compounds — but the box for one giant token covers the whole compound. UI needs to handle long horizontal taps gracefully. Mitigation: this is a UI concern, surface in Task 5/6, not OCR.
- **Most-likely-wrong assumption:** That `image.pngData()` is fast enough for hashing on every call. For 4K manga pages it's ~5–20 ms. Probably fine, but if it shows up in profiling, switch to hashing the `CGImage` data provider bytes directly without re-encoding. Defer.
- **Edge case:** Pages with rotated text (vertical sound effects, sideways panels). Vision handles 90°-rotated text reasonably with `.accurate`, but tilted text fails. Acceptable for MVP — vision doc explicitly excludes sound-effect text.
