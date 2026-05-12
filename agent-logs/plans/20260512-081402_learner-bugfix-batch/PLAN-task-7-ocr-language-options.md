---
task: 7
task_name: "ocr-language-options"
status: completed
created: 2026-05-12
steps_total: 5
steps_completed: 5
estimated_files: 6
parallelizable_with: [4, 5]
depends_on: []
---

## Goal

Give the user OCR control to address two practical problems: (a) Vision's `usesLanguageCorrection` corrupting uppercase German with umlauts (e.g., "ÜBERTROFFEN" → "BERTROFFEN" or "UBERTROFFEN"), and (b) single-language OCR missing mixed scripts (e.g., German speech with Japanese SFX). Add two settings: a "Disable language correction" toggle and an OCR-languages multi-select.

## Acceptance Criteria

- [ ] A new toggle "Disable language correction" appears in the Learner Mode section of Settings. Defaults OFF (correction enabled, current behavior).
- [ ] When the toggle is ON, `VisionOCRService.recognize(...)` passes `request.usesLanguageCorrection = false`.
- [ ] The existing OCR-languages single-select becomes a multi-select. Storage key changes from `Learner.ocrLanguages` (String) to `Learner.ocrLanguagesList` (`[String]` JSON-encoded). On first launch, a migration copies the old String key into a single-element array under the new key, then removes the old key.
- [ ] With the multi-select set to `["de-DE", "ja-JP"]`, both German and Japanese text on the same page are recognized.
- [ ] After toggling either setting, re-OCRing a page (Task 6 menu item) reflects the change.
- [ ] `OCRServiceTests` continue to pass; new unit test covers the languages-array passthrough.

## What This Is Not

- No automatic OCR-engine swap to Apple Vision RT, Tesseract, or any non-Apple OCR. Stays on `VNRecognizeTextRequest`.
- No diacritic-stripping anywhere in the lemma normalize path (Task 4 deliberately preserves diacritics; this task keeps that contract).
- No per-manga override of OCR languages (out of scope; the user can still set them per-manga via the existing reader settings if the underlying key is read by both — but adding a new tier is not needed for the reported bugs).
- No confidence-threshold slider (user did not select that option in Q7).

## Approach

- The OCR call site `LearnerOverlayCoordinator.swift:177-183` (`ocrLanguages`) currently reads a single `String?` from `Learner.ocrLanguages`. Replace with a function reading the JSON-encoded array under `Learner.ocrLanguagesList`, with a one-shot migration that fires inside the same function the first time it's called (or in `LearnerGate.migrateLegacy...` extended). Defaults to `["de-DE"]` when missing.
- The new "disable language correction" UserDefaults boolean is read inside `VisionOCRService.recognize(...)` just before `request.usesLanguageCorrection = true` at line 117. Key: `Learner.disableLanguageCorrection` (Bool, default false).
- Settings UI: add the new controls to both the global Learner section (`iOS/New/Views/Settings/Settings.swift` around the existing `LEARNER_MODE` block — find with `grep -n 'Learner.ocrLanguages' iOS/New/Views/Settings/Settings.swift`) and the per-manga reader settings (`iOS/New/Views/Reader/ReaderSettingsView.swift:400-411`). For the multi-select, use SwiftUI's native multi-select pattern — there isn't a `.multiSelect` in the existing `SettingView` framework based on the explore, so fall back to a custom view: a section with five toggle rows (de/en/ja/fr/es), each writing into the array under the new key. Keep the list short (the five existing languages from line 408).

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Re-OCR controls to add | Disable-language-correction toggle + OCR-language multi-select | User answered Q7 |
| 2 | Storage of multi-select | New key `Learner.ocrLanguagesList` as JSON-encoded `[String]` | Avoid CoreData/UserDefaults array type quirks; explicit JSON is easy to test |
| 3 | Migration from old key | Read `Learner.ocrLanguages` once; if non-empty, write `[that]` to new key; delete old key | One-shot, idempotent, no user action required |
| 4 | Default languages | `["de-DE"]` | Matches current default at coordinator line 182 |
| 5 | Default for disable-correction | `false` (correction stays enabled) | Don't surprise existing users |
| 6 | Multi-select UI | Custom SwiftUI section with five toggle rows | `SettingView` framework lacks multi-select; custom is simpler than extending the framework |
| 7 | Language list | Existing five: de-DE, en-US, ja-JP, fr-FR, es-ES | Matches `ReaderSettingsView.swift:407-408` |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | Shared/Learner/Reader/LearnerOverlayCoordinator.swift | Replace `ocrLanguages()` body (lines 177-183) to read JSON-encoded array from `Learner.ocrLanguagesList`. Run a one-time migration from `Learner.ocrLanguages` (String) → `Learner.ocrLanguagesList` (`[String]`). |
| MODIFY | Shared/Learner/OCR/VisionOCRService.swift | Read `UserDefaults.standard.bool(forKey: "Learner.disableLanguageCorrection")` once at the top of `recognize(...)`; pass `!disabled` into `request.usesLanguageCorrection` at line 117. |
| MODIFY | iOS/New/Views/Settings/Settings.swift | In the existing Learner section, replace the single-select for OCR languages with a custom multi-select subview (named e.g. `LearnerOCRLanguagesPicker` inside the file or alongside it). Add the "Disable language correction" toggle row using the existing `SettingView` of `.toggle`. |
| MODIFY | iOS/New/Views/Reader/ReaderSettingsView.swift | Same two controls per-manga (lines 401-412 region). Reuse the same `LearnerOCRLanguagesPicker` view. |
| MODIFY | AidokuTests/OCRServiceTests.swift | Add: a test that passes `languages: ["de-DE", "ja-JP"]` and asserts the result includes recognized text from both scripts (use the existing fixture infra, see graph community 122 `VisionOCRService`/`loadFixture`). Plus a test that sets `Learner.disableLanguageCorrection = true` and asserts the request received `usesLanguageCorrection = false` (may require small refactor to expose the request configuration for inspection — alternative: skip and rely on integration). |
| CREATE | iOS/New/Views/Reader/LearnerOCRLanguagesPicker.swift | New SwiftUI view rendering a five-row toggle list bound to the JSON-encoded array under Learner.ocrLanguagesList |

## Implementation Steps

- [x] **Step 1: Multi-language read + migration in coordinator**
  - **What:** replace `ocrLanguages()` with an implementation that JSON-decodes `Learner.ocrLanguagesList` (Data) → `[String]`, defaulting to `["de-DE"]`. Before reading, if `Learner.ocrLanguagesList` is missing AND `Learner.ocrLanguages` (String) is present, encode `[oldValue]` to JSON, write under the new key, remove the old key.
  - **Files:** `Shared/Learner/Reader/LearnerOverlayCoordinator.swift`
  - **Verify by:** unit test: write `Learner.ocrLanguages = "ja-JP"`, call `ocrLanguages()`, expect `["ja-JP"]`, expect old key gone, expect new key present.

- [x] **Step 2: Wire disable-language-correction into Vision**
  - **What:** in `VisionOCRService.recognize(...)`, read `UserDefaults.standard.bool(forKey: "Learner.disableLanguageCorrection")` once near line 115, then change line 117 to `request.usesLanguageCorrection = !disableCorrection`.
  - **Files:** `Shared/Learner/OCR/VisionOCRService.swift`
  - **Verify by:** integration test on a fixture image where correction currently mangles a word → flip the flag → re-recognize → confirm the word is preserved.

- [x] **Step 3: Custom multi-select view**
  - **What:** add `struct LearnerOCRLanguagesPicker: View` (file: `iOS/New/Views/Reader/LearnerOCRLanguagesPicker.swift` — new file). Renders a five-row toggle list bound to the array under `Learner.ocrLanguagesList`. Each toggle reads/writes the JSON-encoded array. Disable the last-remaining toggle (can't deselect all — enforce at least one).
  - **Files:** new `iOS/New/Views/Reader/LearnerOCRLanguagesPicker.swift`
  - **Verify by:** open the settings page in a SwiftUI preview, toggle items, persist + re-render.

- [x] **Step 4: Embed pickers + correction toggle in both settings screens**
  - **What:** in `Settings.swift` (global Learner block) and `ReaderSettingsView.swift` (per-manga, lines 401-412), replace the existing single-select with the new picker, and add the "Disable language correction" `.toggle` SettingView using key `Learner.disableLanguageCorrection`.
  - **Files:** `iOS/New/Views/Settings/Settings.swift`, `iOS/New/Views/Reader/ReaderSettingsView.swift`
  - **Verify by:** both screens render correctly; changes persist and round-trip across app restarts.

- [x] **Step 5: OCR tests**
  - **What:** add unit cases in `OCRServiceTests.swift` for the language-array passthrough using a fixture image containing both German and Japanese text. Add a localized fixture if one doesn't exist (the graph references `BundleLocator` / `loadFixture` — reuse).
  - **Files:** `AidokuTests/OCRServiceTests.swift`
  - **Verify by:** `xcodebuild test -only-testing:AidokuTests/OCRServiceTests` passes.

## Testing Strategy

- New `OCRServiceTests` cases using mixed-script fixture images.
- Unit test for the migration logic (deterministic UserDefaults round-trip).
- Manual smoke: enable both German + Japanese OCR; open a manga page with SFX; re-OCR via Task 6; verify SFX overlay regions appear.

## Risks

- **Most complex:** Vision's behavior when given multiple recognition languages. The docs say it tries each in order; in practice, mixed-script accuracy on the same page is mediocre. Mitigation: document the trade-off in the footer of the multi-select section; advise users that more languages = slower + lower accuracy per language.
- **Assumption most likely wrong:** that disabling `usesLanguageCorrection` actually fixes the umlaut mangling. It MIGHT make it worse on other words. We're shipping a knob the user explicitly asked for; the correctness of "is this fixing the BERTROFFEN bug" is the user's to determine after trying it.
- **Easy-to-miss edge case:** an existing user with `Learner.ocrLanguages` unset (i.e., default `de-DE` is used at line 182). The migration in Step 1 must default to `["de-DE"]` in that case, NOT to an empty array (which would break OCR entirely).
