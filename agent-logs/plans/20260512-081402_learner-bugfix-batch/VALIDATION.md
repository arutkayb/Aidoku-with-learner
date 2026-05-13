# Plan Validation: 20260512-081402_learner-bugfix-batch

**Date:** 2026-05-12
**Plans validated:** 7
**Overall:** WARN

Overall semantics (post-fix):
- **PASS** — no findings remain, or every FAIL/WARN was fix-mechanical/fix-rewrite and cleared.
- **WARN** — at least one escalate-only WARN remains; no FAILs remain.
- **FAIL** — at least one FAIL remains (escalate-only or fix that did not clear).

Notes on this run:
- This is the second validation pass over the bundle, run after a `/tackle-validation` pass that already resolved 16 prior findings (path corrections, test-file retargets, `parallelizable_with` cleanups, xcdatamodel version bump, etc.). See the prior report in git/edit history if needed.
- One new finding was introduced by the tackle pass (Task 3's Files Touched got a step orphan after a row removal). Auto-fixed in this run.

## 1. Precondition Sweep

PASS — every MODIFY path resolves on disk and every CREATE path has an existing parent directory.

- PASS: Task 1 — six MODIFY paths exist: `LearnerOverlayCoordinator.swift`, `LearnerStrings.swift`, `ReaderSettingsView.swift`, `ReaderPagedViewController.swift`, `AidokuTests/LearnerOverlayTests.swift`, `Shared/Localization/en.lproj/Localizable.strings`.
- PASS: Task 2 — four MODIFY + one CREATE (`AidokuTests/ReaderGestureDelegateTests.swift`, parent dir exists).
- PASS: Task 3 — three MODIFY (after this run added the `LearnerOverlayTests.swift` row).
- PASS: Task 4 — four MODIFY paths exist. The row 3 path cell contains a parenthetical (`...VocabularyManagerTests.swift (or wherever ...)`) but the leading path resolves on disk.
- PASS: Task 5 — one CREATE (`0.9.1.xcdatamodel/contents`, parent `Shared/Aidoku.xcdatamodeld` exists) plus seven MODIFY paths (`.xccurrentversion`, `VocabularyEntryObject.swift`, `Shared/Managers/CoreData/CoreDataManager+Vocabulary.swift`, `WordLookupViewModel.swift`, `WordLookupSheet.swift`, `VocabularyListView.swift`, `WordLookupViewModelTests.swift`).
- PASS: Task 6 — six MODIFY paths exist.
- PASS: Task 7 — five MODIFY + one CREATE (`LearnerOCRLanguagesPicker.swift`, parent dir `iOS/New/Views/Reader/` exists).

Template/pattern references in Decision Registers (cited line ranges in `LearnerOverlayCoordinator.swift`, `LearnerOverlayView.swift`, `VocabularyEntryObject.swift`, `WordLookupSheet.swift`, `ReaderSettingsView.swift`) all resolve to existing files; line numbers spot-checked in prior pass.

## 2. Dependency Check

PASS

- PASS: Inter-task dependency graph acyclic. Roots: `{1, 2, 4, 7}`. `3` and `6` depend on `2`; `5` depends on `4`.
- PASS: No task appears in both `depends_on` and `parallelizable_with` of another.
- PASS: No cross-task file overlap among `parallelizable_with` pairs. Verified pairs:
  - Task 2 vs 4: disjoint file sets.
  - Task 3 vs 4: disjoint file sets.
  - Task 3 vs 5: disjoint file sets.
  - Task 4 vs 2, 3, 6, 7: disjoint file sets.
  - Task 5 vs 6, 7: disjoint file sets.
  - Task 6 vs 4, 5: disjoint file sets.
  - Task 7 vs 4, 5: disjoint file sets.
- PASS: No intra-plan implicit file conflicts. Each plan's steps touch disjoint files within the plan.
- INFO: Asymmetric `parallelizable_with` between Task 3 (lists 5) and Task 5 (does NOT list 3). Pre-existing in the original plan; not flagged by any check rule. Not blocking.

## 3. Assumption Stress-Test

PASS

- PASS: Decision Register cites in tasks 1-7 reference existing files; line refs spot-checked in prior pass match current source (notably `LearnerOverlayCoordinator.swift:164-175`, `:177-183`, `:188-203`; `LearnerOverlayView.swift:239`, `:221-234`; `VocabularyEntryObject.swift:36-38`, `:73`).
- PASS: Plans created 2026-05-12; latest commit 2026-05-11 15:23 — 0 commits since plan creation. Plans are fresh.
- INFO: Task 1 risk note "SettingView of .select correctly posting the configured notification" — external/unverifiable; manual on-device check required.
- INFO: Task 6 risk note "ScrollViewReader.scrollTo inside a `.medium()` detent sheet" — external/unverifiable.
- INFO: Task 7 risk note "Vision's mixed-script accuracy" — external/unverifiable.

## 4. Completeness Check

PASS (with three escalate-only WARNs on manual-smoke steps that have `Files: none` by design)

### Acceptance criteria coverage

- PASS: Each acceptance criterion in tasks 1-7 maps to at least one step's `What` or `Verify by`.

### Step-to-file mapping

- PASS: Every step's Files-field entry resolves to a row in its plan's Files Touched table.
- WARN: Task 2 Step 5 (manual smoke) has `Files: none`. Resolution: **Escalated** — manual verification step by design (escalate-only).
- WARN: Task 3 Step 3 (manual smoke) has `Files: none`. Resolution: **Escalated**.
- WARN: Task 4 Step 4 (manual smoke) has `Files: none`. Resolution: **Escalated**.

### Files Touched completeness (orphan files)

- PASS: Every file in each plan's Files Touched is referenced by at least one step.

### Frontmatter consistency

- PASS: All `estimated_files` values match the post-fix row count.
  - Task 1: 6 rows / `estimated_files: 6`.
  - Task 2: 5 rows / `estimated_files: 5`.
  - Task 3: 3 rows / `estimated_files: 3` (auto-fixed this run, was 2 after row removal then restored to 3 after new row).
  - Task 4: 4 rows / `estimated_files: 4`.
  - Task 5: 8 rows / `estimated_files: 8`.
  - Task 6: 6 rows / `estimated_files: 6`.
  - Task 7: 6 rows / `estimated_files: 6`.
- PASS: All `steps_total` values match actual step counts (1→6, 2→6, 3→4, 4→4, 5→6, 6→5, 7→5).

### Testing Strategy coverage

- PASS: Test commands are concrete (`xcodebuild test -only-testing:AidokuTests/<Suite>` form). Test files exist or are explicitly CREATE rows.

## 5. Failure Pattern Pre-Screen

PASS (with one INFO carryover)

- PASS: No step exceeds 5 files in its Files field.
- PASS: Every `Verify by` is non-empty and contains a concrete command, a specific observable check, or maps to a named acceptance criterion.
- PASS: Decision Register rationales cite user answers (Q1-Q7), specific files/lines, or stated conventions. No TBD entries.
- PASS: No CREATE-order dependency gap detected.
- INFO: `check-git-state.sh` from the skill toolkit errored (`touched_files[@]: unbound variable`) on first pass. Carried forward as INFO; not a plan issue.

## Auto-fixes Applied

| # | Check | Plan file | Edit | Cleared? |
|---|-------|-----------|------|----------|
| 1 | Completeness | PLAN-task-3-live-text-coexistence.md | Appended MODIFY row for `AidokuTests/LearnerOverlayTests.swift` to Files Touched (Step 4 referenced it; row had been dropped during the prior orphan-removal in `/tackle-validation`) | yes |
| 2 | Completeness | PLAN-task-3-live-text-coexistence.md | Reconciled frontmatter `estimated_files: 2` → `3` after the appended row | yes |

## Escalations (require human / re-plan)

| # | Check | Severity | Plan file | Finding | Why not auto-fixed |
|---|-------|----------|-----------|---------|--------------------|
| 1 | Completeness | WARN | PLAN-task-2-zoom-and-tap-conflict.md | Step 5 (manual smoke) has `Files: none` | escalate-only: manual verification step by design |
| 2 | Completeness | WARN | PLAN-task-3-live-text-coexistence.md | Step 3 (manual smoke) has `Files: none` | escalate-only |
| 3 | Completeness | WARN | PLAN-task-4-vocab-text-cleaning.md | Step 4 (manual smoke) has `Files: none` | escalate-only |
| 4 | Assumption Stress-Test | INFO | PLAN-task-1-learner-gate-tristate.md | `SettingView .select` posts the configured notification — external/unverifiable | escalate-only |
| 5 | Assumption Stress-Test | INFO | PLAN-task-6-sentence-focus-and-reocr.md | `ScrollViewReader.scrollTo` works inside `.medium()` detent sheet — external/unverifiable | escalate-only |
| 6 | Assumption Stress-Test | INFO | PLAN-task-7-ocr-language-options.md | Vision mixed-script accuracy — external/unverifiable | escalate-only |
| 7 | Dependency | INFO | PLAN-task-3 / PLAN-task-5 | Asymmetric `parallelizable_with` (3 lists 5; 5 does not list 3). Pre-existing | not a check-rule finding; informational |
| 8 | Failure Pattern | INFO | (validator) | `check-git-state.sh` skill helper has an `unbound_variable` bug | escalate-only: skill-toolkit issue, not a plan issue |

## Summary

### Blockers (must fix before execution)

None.

### Warnings (should review)

1. Three manual-smoke steps (`task 2 Step 5`, `task 3 Step 3`, `task 4 Step 4`) have `Files: none`. Acceptable for manual verification but they cannot be lint-tracked.

### Info

1. Three external/unverifiable assumptions in risk sections (SettingView notification posting, ScrollViewReader inside sheet, Vision mixed-script accuracy) — verify on device during smoke.
2. Asymmetric `parallelizable_with` between Tasks 3 and 5 (pre-existing); no check-rule violation, noted for awareness.
3. `check-git-state.sh` skill helper has an unbound-variable bug — file against the skill toolkit, not a plan issue.
4. `execution-state.json` in the plan folder still carries pre-tackle `parallelizable_with` values (outside the validator's edit scope). `/execute` should re-derive scheduling from the plan frontmatter or the user should regenerate state.
