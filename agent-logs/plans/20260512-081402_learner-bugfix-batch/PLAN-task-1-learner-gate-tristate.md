---
task: 1
task_name: "learner-gate-tristate"
status: completed
created: 2026-05-12
steps_total: 6
steps_completed: 6
estimated_files: 6
parallelizable_with: []
depends_on: []
---

## Goal

Make the per-manga Learner toggle a tri-state (Inherit / On / Off) that can override the global toggle in both directions, and fix the in-session refresh-notification key mismatch.

## Acceptance Criteria

- [ ] With global Learner ON and a manga set to "Off", opening that manga does NOT attach the overlay.
- [ ] With global Learner OFF and a manga set to "On", opening that manga DOES attach the overlay.
- [ ] With per-manga set to "Inherit", behavior matches the global toggle exactly.
- [ ] Flipping the per-manga toggle from the Reader settings sheet while reading immediately attaches/detaches the overlay on the visible page (no chapter reload required).
- [ ] Flipping the global toggle in Settings while reading a manga with "Inherit" mode immediately attaches/detaches the overlay.
- [ ] Existing UserDefaults entries written by the previous boolean-only UI are migrated to `.on` (true) or removed (false) on first launch under the new build.
- [ ] `swift build` and the existing Learner unit test target compile.

## What This Is Not

- No change to the Settings tab global toggle layout, copy, or the global UserDefaults key (`Learner.globallyEnabled`).
- No new entry for "global default for new manga" — Inherit is the default.

## Approach

- The gate predicate currently lives in `Shared/Learner/Reader/LearnerOverlayCoordinator.swift:164-175` (`isLearnerEnabled(for:)`) and uses `perManga || global` with a `Bool` per-manga key. Replace with tri-state logic backed by an enum-encoded string.
- Per-manga state moves from `Bool` (UserDefaults key `Learner.enabled.{mangaId}`) to a `String` in `Learner.mode.{mangaId}` with values `"inherit"`, `"on"`, `"off"`. Default (key absent) = `"inherit"`. Old `Learner.enabled.{mangaId}` key is read once on first access and migrated: `true → "on"`, `false → key removed`. Old key is then deleted to avoid future confusion.
- The per-manga UI in `iOS/New/Views/Reader/ReaderSettingsView.swift:388-421` (currently a SwiftUI `SettingView` of `.toggle`) becomes a SwiftUI `Picker` (segmented) bound to the new key. Existing `SettingView` framework supports `.select` (used elsewhere in the same file at line 57-77 for reading mode) — reuse that pattern; new strings localized under `LEARNER_MODE_INHERIT`, `LEARNER_MODE_ON`, `LEARNER_MODE_OFF`.
- Mid-session refresh: `iOS/UI/Reader/Readers/Paged/ReaderPagedViewController.swift:163-172` listens on notification name `Learner.enabled.{sourceId}.{mangaId}` but the setting fires `Learner.enabled.{mangaId}` (single key). Replace both notification names with the new `Learner.mode.{mangaId}` key, plus continue to observe `Learner.globallyEnabled`. Coordinator must re-evaluate the gate and either attach or `deactivate` the overlay on the visible page.
- Add a `LearnerGateMode` enum + `LearnerGate` helper in `Shared/Learner/LearnerStrings.swift` (the existing shared-Learner-helpers file) so coordinator + reader observer + tests share one implementation.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Gate semantics | Tri-state per-manga (Inherit / On / Off) | User answered Q1 |
| 2 | Storage key | New `Learner.mode.{mangaId}` (String) | Old key was Bool — keep history clean, avoid encoding `nil`-vs-`false` ambiguity |
| 3 | Migration | One-time on first read per mangaId: `true → "on"`, `false → delete` | "Leave existing alone" was about Vocabulary (Task 4); the gate must migrate because the old boolean carries intent |
| 4 | Default value | `"inherit"` (key absent) | Matches the recommended UX; new manga inherit global |
| 5 | UI control | SwiftUI `SettingView` of `.select` with three values | Existing pattern at `ReaderSettingsView.swift:57-77` |
| 6 | Notification name | `Learner.mode.{mangaId}` (matches the actual write key) | Fixes the silent mismatch in `ReaderPagedViewController.swift:164` |
| 7 | LearnerGate helper location | `Shared/Learner/LearnerStrings.swift` | Already the shared cross-task helper file; avoid new file |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | Shared/Learner/Reader/LearnerOverlayCoordinator.swift | Replace `isLearnerEnabled(for:)` body to call `LearnerGate.isEnabled(mangaId:)`; one migration call from old Bool key on first access |
| MODIFY | Shared/Learner/LearnerStrings.swift | Add `LearnerGateMode` enum (`.inherit`, `.on`, `.off`) and `LearnerGate.isEnabled(mangaId:)` + `LearnerGate.modeKey(for:)` + one-shot `migrateLegacyBoolKey(mangaId:)` |
| MODIFY | iOS/New/Views/Reader/ReaderSettingsView.swift | Replace `.toggle` SettingView at lines 391-398 with `.select` over `["inherit","on","off"]`; update footer copy; remove `UserDefaultsBool(key: "Learner.enabled.\(mangaId)")` observer (line 43) and rebind to a String-backed observer or use `SettingView`'s notification only |
| MODIFY | iOS/UI/Reader/Readers/Paged/ReaderPagedViewController.swift | Line 164: change `learnerToggleKey` to `Learner.mode.\(viewModel.manga.key)`; line 165-170 refreshLearner closure: call `LearnerOverlayCoordinator.shared.deactivate(...)` AND `notifyLearnerOfImage()` based on `LearnerGate.isEnabled(...)` — so flipping off-while-reading clears the overlay |
| MODIFY | AidokuTests/LearnerOverlayTests.swift | Add tests to the existing `@Suite struct LearnerCoordinatorTests` for the tri-state matrix: 9 combinations of (global on/off × per-manga inherit/on/off) → expected enabled bool, plus a legacy-migration case |
| MODIFY | Shared/Localization/en.lproj/Localizable.strings | Add `LEARNER_MODE_INHERIT`, `LEARNER_MODE_ON`, `LEARNER_MODE_OFF` keys alongside the existing `LEARNER_MODE_ENABLE` entry (line 814) |

## Implementation Steps

- [x] **Step 1: Introduce `LearnerGateMode` and `LearnerGate` helper**
  - **What:** add `enum LearnerGateMode: String { case inherit, on, off }` and `enum LearnerGate { static func isEnabled(mangaId:) -> Bool; static func mode(for:) -> LearnerGateMode; static func modeKey(for:) -> String; static func legacyBoolKey(for:) -> String; static func migrateLegacyBoolKeyIfNeeded(_:) }` to `LearnerStrings.swift`. No callers yet.
  - **Files:** `Shared/Learner/LearnerStrings.swift`
  - **Verify by:** `swift build` succeeds; new functions referenced nowhere yet (warning is ok).

- [x] **Step 2: Switch coordinator to use `LearnerGate`**
  - **What:** rewrite `LearnerOverlayCoordinator.isLearnerEnabled(for:)` to call `LearnerGate.migrateLegacyBoolKeyIfNeeded(mangaId); return LearnerGate.isEnabled(mangaId: mangaId)`. Keep the `Learner.enabledGlobally` side-effect (vocabulary-tab visibility) unchanged.
  - **Files:** `Shared/Learner/Reader/LearnerOverlayCoordinator.swift`
  - **Verify by:** unit test `Learner.enabled.foo = true (legacy) → LearnerGate.mode(for:"foo") == .on` and key removed from UserDefaults.

- [x] **Step 3: Replace per-manga Toggle UI with tri-state Picker**
  - **What:** in `ReaderSettingsView.swift`, replace the `.toggle` SettingView at 391-398 with a `.select` SettingView using values `["inherit","on","off"]` and titles `[NSLocalizedString("LEARNER_MODE_INHERIT"), NSLocalizedString("LEARNER_MODE_ON"), NSLocalizedString("LEARNER_MODE_OFF")]`, key `Learner.mode.\(mangaId)`, notification name same. Remove the `learnerEnabled` `UserDefaultsBool` state object (line 43) and adjust the gate at line 401 (`if isPaged && learnerEnabled.value`) to read the new mode (`LearnerGate.mode(for: mangaId) != .off`).
  - **Files:** `iOS/New/Views/Reader/ReaderSettingsView.swift`
  - **Verify by:** open ReaderSettings on a manga, toggle through three values, see the value persist in `defaults read group.com.skitty.Aidoku Learner.mode.{mangaId}`.

- [x] **Step 4: Fix mid-session refresh notification name**
  - **What:** in `ReaderPagedViewController.swift:163-172`, change the observed notification name to `"Learner.mode.\(viewModel.manga.key)"` (drop sourceId composite). Update the `refreshLearner` closure to read `LearnerGate.isEnabled(mangaId:)`; if disabled, call `LearnerOverlayCoordinator.shared.deactivate(for:container:)` on every visible page's context; if enabled, call `pageView.notifyLearnerOfImage()`.
  - **Files:** `iOS/UI/Reader/Readers/Paged/ReaderPagedViewController.swift`
  - **Verify by:** open a manga, toggle per-manga to Off mid-reading → overlay disappears immediately; toggle to On → overlay re-attaches.

- [x] **Step 5: Add localization strings**
  - **What:** add `LEARNER_MODE_INHERIT`, `LEARNER_MODE_ON`, `LEARNER_MODE_OFF` to `Shared/Localization/en.lproj/Localizable.strings` alongside the existing `LEARNER_MODE_ENABLE` entry at line 814. (Other locales fall back to en at runtime; adding translations for the 39 other locales is out of scope here.)
  - **Files:** `Shared/Localization/en.lproj/Localizable.strings`
  - **Verify by:** `grep -n "LEARNER_MODE_INHERIT" Shared/Localization/en.lproj/Localizable.strings` returns one hit.

- [x] **Step 6: Unit tests for tri-state matrix**
  - **What:** add 9-case test for `(global ∈ {on, off}) × (perManga ∈ {inherit, on, off})` to the existing `@Suite struct LearnerCoordinatorTests` in `AidokuTests/LearnerOverlayTests.swift:141`. Plus one legacy-migration test: write `Learner.enabled.X = true` in UserDefaults → call `LearnerGate.isEnabled(mangaId: "X")` → expect `true` AND `Learner.mode.X == "on"` AND old key removed.
  - **Files:** `AidokuTests/LearnerOverlayTests.swift`
  - **Verify by:** `xcodebuild test -only-testing:AidokuTests/LearnerCoordinatorTests` passes (suite name unchanged; only the file housing it).

## Testing Strategy

- Extend the existing `@Suite struct LearnerCoordinatorTests` defined in `AidokuTests/LearnerOverlayTests.swift:141` (graph community 100). Use the same `@Test` Swift Testing pattern as `OCRServiceTests`/`WordLookupViewModelTests`.
- Each test isolates UserDefaults via a uniquely-namespaced mangaId per test (no shared state, no test ordering issues).
- Run `xcodebuild test -scheme Aidoku -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:AidokuTests/LearnerCoordinatorTests`.

## Risks

- **Most complex:** the in-session refresh path. The coordinator's `setEnabled(_:for:)` (line 145-160) clears all overlays for a mangaId but is currently called from nowhere on user toggle. Wiring `refreshLearner` correctly so that "off → on → off → on" flips don't leak overlay state is the trickiest part. Mitigation: explicit `deactivate(for:container:)` per visible page; do not rely on `setEnabled`.
- **Assumption most likely wrong:** that `SettingView` of `.select` correctly posts the configured notification on change. If it doesn't, add a manual observer on UserDefaults didChange.
- **Easy-to-miss edge case:** the global toggle's `Learner.enabledGlobally` side-effect (vocabulary-tab visibility) — keep this logic in coordinator's `isLearnerEnabled` so the vocab tab still appears the first time a manga's per-manga mode forces it on while global is off.
