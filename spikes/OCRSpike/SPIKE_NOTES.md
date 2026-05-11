# OCR Spike Notes

**Purpose:** Validate `VNRecognizeTextRequest` word-level bounding box accuracy on real German manga pages before integrating into Aidoku.

**Test setup:** iOS 26+ device or simulator. Images in `OCRSpike/TestImages/` (maintainer supplies 5–10 German manga page PNGs).

## Per-Page Accuracy Log

<!-- Maintainer: fill in one row per test image after running the spike app. -->
<!-- Category options:
     A = All words boxed correctly
     B = Minor box errors but words recognized
     C = Major errors / unusable
-->

| Image | Category | Notes |
|-------|----------|-------|
| (image1.png) | — | |
| (image2.png) | — | |
| (image3.png) | — | |
| (image4.png) | — | |
| (image5.png) | — | |

## Observations

- Word-level granularity (whitespace-split + `boundingBox(for: range)`): 
- Line-level fallback quality: 
- Stylized fonts / sound effects accuracy: 
- Performance on simulator: 

## Go / No-Go Decision

<!-- Replace the line below with either GO or NO-GO followed by 1–3 sentences of rationale. -->
<!-- Example: GO — Word boxes aligned on 4/5 test pages; minor misalignment on page 3 (stylized font) but acceptable for MVP. -->

PENDING — Maintainer has not yet run the spike.
