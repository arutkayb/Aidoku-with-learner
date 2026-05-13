# Plan Validation: 20260509-123140_mangadict-mvp

**Date:** 2026-05-09
**Plans validated:** 8 (PLAN-task-1 through PLAN-task-8)
**Overall:** WARN

Overall semantics (post-fix):
- All 8 frontmatter `estimated_files` mismatches were `fix-mechanical` and cleared.
- No FAILs remain.
- Multiple `escalate-only` WARNs remain (cross-task overlaps, orphan rows, frontmatter/body inconsistencies, stale git state).

## 1. Precondition Sweep

11/11 preconditions verified

- PASS — All MODIFY/DELETE file paths in Files Touched tables exist on disk: `Shared/Aidoku.xcdatamodeld/.xccurrentversion`, `Shared/Data/Backup/Backup.swift`, `Shared/Data/Backup/BackupManager.swift`, `Aidoku.xcodeproj/project.pbxproj`, `iOS/UI/Reader/Page/ReaderPageView.swift`, `iOS/UI/Reader/Readers/Paged/ReaderPagedViewController.swift`, `iOS/UI/Reader/ReaderViewController.swift`, `iOS/New/Views/Reader/ReaderSettingsView.swift`, `Shared/Localization/en.lproj/Localizable.strings`, `iOS/SceneDelegate.swift`, `.gitignore`. Resolution: Info.
- PASS — Pattern references resolve: `MangaObject.swift`, `BackupHistory.swift`, `CoreDataManager+Manga.swift`, `CoreDataManager.swift:59-60` (migration setup verified), `ReaderViewController.swift:502` (`openReaderSettings` verified), `ReaderSettingsView.swift:34` (readingMode pattern verified), `AidokuTests/TrackerSyncTests.swift:10` (`import Testing` verified). Resolution: Info.
- PASS — Cross-task forward references resolve via `depends_on` ordering: Task 7's MODIFY of `Shared/Learner/Reader/LearnerOverlayView.swift` is satisfied by Task 5's CREATE (Task 7 depends_on [5]). Resolution: Info.
- INFO — Task 6 Decision #9 cites "MarkdownView (already imported in `ReaderPageView.swift:10`)". Line 10 is `import MarkdownUI` (the third-party SPM); the local `MarkdownView` wrapper is referenced at `ReaderPageView.swift:27` and `:464`, with the wrapper itself defined at `iOS/UI/Reader/Page/MarkdownView.swift`. Decision intent (use existing wrapper) is correct, line citation is approximate. Resolution: Escalated (informational).
- PASS — Parent dirs that don't yet exist (`spikes/`, `Shared/Learner/`, `iOS/UI/Learner/`, `AidokuTests/Fixtures/`) are all created implicitly by the first CREATE in their owning task. No prior-step requirement exists for parent creation in any plan. Resolution: Info.

## 2. Dependency Check

WARN

- PASS — Intra-plan step dependencies in all 8 plans: no cycles, no missing references, all `Depends on` values resolve to existing steps. Resolution: Info.
- FAIL — None.
- WARN — Task 8 frontmatter declares `parallelizable_with: [5, 6, 7]` but Step 6's body says "Depends on: Task 6" (file `iOS/UI/Learner/WordLookupSheet.swift`, MODIFY of file CREATED by Task 6). Body and frontmatter contradict each other. `PLAN-task-8-vocab-flashcards.md`. Resolution: Escalated (frontmatter vs. step-body conflict; needs human decision — likely move Task 6 from `parallelizable_with` into `depends_on`).
- WARN — Cross-task file overlap risk for pairs that are mutually parallelizable AND modify the same file:
  - Tasks 2 / 3 / 4 (all mutually parallelizable, depend on Task 1) all modify `Aidoku.xcodeproj/project.pbxproj`. `PLAN-task-2`, `PLAN-task-3`, `PLAN-task-4`. Resolution: Escalated.
  - Tasks 6 / 7 (mutually parallelizable, depend on Tasks 2/3/5) both modify `Aidoku.xcodeproj/project.pbxproj`, `Shared/Localization/en.lproj/Localizable.strings`, and `iOS/UI/Reader/ReaderViewController.swift`. Resolution: Escalated.
  - Tasks 5 / 8, 6 / 8, 7 / 8 (Task 8 lists 5/6/7 in `parallelizable_with`) all share `Aidoku.xcodeproj/project.pbxproj` and `Shared/Localization/en.lproj/Localizable.strings`. Resolution: Escalated.
  - Tasks 6 / 8 additionally share `iOS/UI/Learner/WordLookupSheet.swift` (Task 6 CREATE, Task 8 MODIFY). Resolution: Escalated (this is the same finding as the frontmatter conflict above).
- INFO — Tasks 5 / 6 / 7 all modify `iOS/UI/Reader/ReaderViewController.swift`, but Task 5 is sequential before 6/7 (5 is in `depends_on` of both 6 and 7). Only the 6 ↔ 7 parallel pairing is at conflict-risk; 5 is fine. Resolution: Info.

## 3. Assumption Stress-Test

7/7 assumptions still hold

- PASS — Task 2 Decision #1 cites `CoreDataManager.swift:59-60`; verified the file at those lines sets `shouldMigrateStoreAutomatically = true` and `shouldInferMappingModelAutomatically = true`. Resolution: Info.
- PASS — Task 2 Decision #4 cites `+Manga, +History, +Track extensions`; all three files exist at `Shared/Managers/CoreData/CoreDataManager+{Manga,History,Track}.swift`. Resolution: Info.
- PASS — Task 2 Decision #11 cites `BackupHistory.swift`; file exists at `Shared/Data/Backup/Models/BackupHistory.swift`. Resolution: Info.
- PASS — Task 2 Decision #13 / Task 3 Decision #12 (Swift Testing framework) cite `AidokuTests/TrackerSyncTests.swift:10`; verified `import Testing` is on that line. Resolution: Info.
- PASS — Task 5 Decision #2 cites `ReaderSettingsView.swift:34` (readingMode pattern); verified line 33-34 builds the per-manga key `Reader.readingMode.\(mangaId)`. Resolution: Info.
- PASS — Task 6 Decision #1 cites `ReaderViewController.openReaderSettings` at line 502; verified function defined at exactly line 502. Resolution: Info.
- INFO — Task 6 Decision #9: line citation `ReaderPageView.swift:10` is the `MarkdownUI` SPM import; the local `MarkdownView` wrapper usage is at line 27 and 464. Pattern intent is verifiable but line offset is misleading. Resolution: Escalated (informational).
- PASS — Stale plan detection: plan `created: 2026-05-09`; latest commit `2026-05-09 14:30:22 +0900`. Same-day commit, no stale risk identified. Resolution: Info.

## 4. Completeness Check

- PASS — Acceptance criteria coverage: every checkbox AC across all 8 plans maps to at least one Implementation Step, except passive-state ACs (e.g. Task 2's "FlashcardState is intentionally NOT in the backup") which are inherently covered by the absence of corresponding insertion code. Resolution: Info.
- PASS — Test command concreteness: every plan with tests includes a concrete `xcodebuild ... test ... -only-testing:...` command in Testing Strategy. Resolution: Info.
- WARN — Step references a file not in Files Touched: Task 2 Step 7 modifies `Shared/Localization/en.lproj/Localizable.strings` (adds `LEARNER_VOCABULARY`, etc.), but that file is absent from Task 2's Files Touched table. `PLAN-task-2-data-model.md`. Resolution: Escalated (recipe preconditions not met: verb "Add" maps to CREATE per recipe, but file already exists on disk — applying recipe verbatim would write a wrong action; demote rather than invent).
- WARN — Step references a file not in Files Touched: Task 5 Step 7 references `iOS/UI/Reader/Readers/Paged/ReaderPageViewController.swift` (NOT the same file as `ReaderPagedViewController.swift` which IS in the table; the per-page VC vs. the parent paged VC are distinct files). `PLAN-task-5-reader-overlay.md`. Resolution: Escalated (recipe preconditions not met: no verb in Step 7's What text — "constructs", "assigns", "wire" — appears in the recipe's CREATE/MODIFY/DELETE verb lists; "could not infer action verb").
- WARN — Files Touched orphan (no step modifies the file): Task 5 lists `iOS/UI/Reader/ReaderViewController.swift` (intent: add Learner toggle button) but no implementation step body modifies it. `PLAN-task-5-reader-overlay.md`. Resolution: Escalated (recipe preconditions not met: 0 steps mention basename `ReaderViewController` — the toolbar-button work mentioned in Approach was deferred but never assigned a step).
- WARN — Files Touched orphan: Task 3 lists `Shared/Localization/en.lproj/Localizable.strings` but no step body mentions it. Resolution: Escalated (orphan file: 0 steps mention basename).
- WARN — Files Touched orphans (project.pbxproj): Tasks 3, 5, 6, 7, 8 each list `Aidoku.xcodeproj/project.pbxproj` MODIFY but no step body explicitly handles it (Tasks 2 and 4 do, in Step 6 and Step 4 respectively). Resolution: Escalated (orphan: 0 steps mention basename `project.pbxproj`).
- WARN — Files Touched orphans (Localizable.strings): Tasks 7, 8 list `Shared/Localization/en.lproj/Localizable.strings` MODIFY but no step body modifies it. Resolution: Escalated (orphan: 0 steps mention basename).
- PASS (after fix) — Frontmatter consistency for `estimated_files`: all 8 plans had a mismatch between frontmatter value and Files Touched row count. Auto-fix reconciled each frontmatter value to actual row count. Resolution: Fixed.
- PASS — Frontmatter consistency for `steps_total`: every plan's frontmatter `steps_total` matches the body step count. Resolution: Info.

## 5. Failure Pattern Pre-Screen

- PASS — No oversized steps (all steps touch ≤ 5 files). Resolution: Info.
- PASS — No "Verify by" entries are missing. Most use concrete `xcodebuild` commands, named tests, or specific observable checks. Borderline cases ("Compile passes" for protocol-only steps; "Tests in Step N" cross-step references) read as acceptable in context — Step N has a concrete command. Resolution: Info.
- PASS — No Decision Register entry has TBD/unresolved rationale. All "Default — ..." entries include explanatory justification, not just the bare word "default". Resolution: Info.
- WARN — Task 2 Step 1 verify command uses `xcodebuild -workspace Aidoku.xcodeproj -scheme Aidoku build`, but `Aidoku.xcodeproj` is a project (no `.xcworkspace` exists in repo). The flag should be `-project Aidoku.xcodeproj`. `PLAN-task-2-data-model.md`. Resolution: Escalated (no recipe applies — incorrect flag, not vague phrasing).
- WARN — Stale git state: `.gitignore` has uncommitted changes; Task 1's Files Touched lists `.gitignore` as MODIFY. Commit or stash before `/execute`. Resolution: Escalated (per check-git-state.sh).
- PASS — Import/dependency gaps: every CREATE-with-imports orders correctly within its plan; cross-task creates are guarded by `depends_on`. Resolution: Info.

## Auto-fixes Applied

| # | Check | Plan file | Edit | Cleared? |
|---|-------|-----------|------|----------|
| 1 | Completeness (frontmatter consistency) | PLAN-task-1-ocr-validation-spike.md | `estimated_files: 5 → 7` | yes |
| 2 | Completeness (frontmatter consistency) | PLAN-task-2-data-model.md | `estimated_files: 11 → 12` | yes |
| 3 | Completeness (frontmatter consistency) | PLAN-task-3-translation-service.md | `estimated_files: 8 → 9` | yes |
| 4 | Completeness (frontmatter consistency) | PLAN-task-4-ocr-service.md | `estimated_files: 4 → 6` | yes |
| 5 | Completeness (frontmatter consistency) | PLAN-task-5-reader-overlay.md | `estimated_files: 7 → 11` | yes |
| 6 | Completeness (frontmatter consistency) | PLAN-task-6-word-lookup-sheet.md | `estimated_files: 4 → 7` | yes |
| 7 | Completeness (frontmatter consistency) | PLAN-task-7-sentence-translation.md | `estimated_files: 4 → 8` | yes |
| 8 | Completeness (frontmatter consistency) | PLAN-task-8-vocab-flashcards.md | `estimated_files: 6 → 11` | yes |

## Escalations (require human / re-plan)

| # | Check | Severity | Plan file | Finding | Why not auto-fixed |
|---|-------|----------|-----------|---------|--------------------|
| 1 | Dependency Check | WARN | PLAN-task-8-vocab-flashcards.md | Frontmatter `parallelizable_with: [5, 6, 7]` contradicts Step 6's "Depends on: Task 6" (Step 6 modifies `WordLookupSheet.swift` which Task 6 CREATEs). | Frontmatter vs. step-body intent ambiguous; needs human decision (most likely move Task 6 from `parallelizable_with` into `depends_on`). |
| 2 | Dependency Check | WARN | PLAN-task-2 / PLAN-task-3 / PLAN-task-4 | Mutually-parallelizable tasks 2/3/4 all modify `Aidoku.xcodeproj/project.pbxproj` — merge-conflict risk if executed in parallel. | Re-architecting parallelism is a planning decision (escalate-only per rules). |
| 3 | Dependency Check | WARN | PLAN-task-6 / PLAN-task-7 | Mutually-parallelizable tasks 6/7 both modify `Aidoku.xcodeproj/project.pbxproj`, `Shared/Localization/en.lproj/Localizable.strings`, and `iOS/UI/Reader/ReaderViewController.swift`. | Same as above. |
| 4 | Dependency Check | WARN | PLAN-task-5 / PLAN-task-6 / PLAN-task-7 / PLAN-task-8 | Task 8 declares `parallelizable_with: [5, 6, 7]` but shares `Aidoku.xcodeproj/project.pbxproj` and `Localizable.strings` with all three; additionally shares `WordLookupSheet.swift` with Task 6. | Re-planning required to either serialize or partition writes. |
| 5 | Completeness | WARN | PLAN-task-2-data-model.md | Step 7 modifies `Shared/Localization/en.lproj/Localizable.strings` but the path is missing from the Files Touched table. | Recipe preconditions not met: verb "Add" maps to CREATE, but file exists on disk — applying recipe verbatim would record a wrong action. |
| 6 | Completeness | WARN | PLAN-task-5-reader-overlay.md | Step 7 modifies `iOS/UI/Reader/Readers/Paged/ReaderPageViewController.swift` (per-page VC, distinct from `ReaderPagedViewController.swift` already listed) but the path is missing from Files Touched. | Recipe preconditions not met: no verb in Step 7's What text matches the recipe's CREATE/MODIFY/DELETE lists. |
| 7 | Completeness | WARN | PLAN-task-5-reader-overlay.md | Files Touched lists `iOS/UI/Reader/ReaderViewController.swift` (toolbar button intent in Approach) but no implementation step body modifies it. | Recipe preconditions not met: 0 steps mention basename. |
| 8 | Completeness | WARN | PLAN-task-3-translation-service.md | Files Touched lists `Shared/Localization/en.lproj/Localizable.strings` but no step body modifies it (orphan). | Recipe preconditions not met: 0 steps mention basename. |
| 9 | Completeness | WARN | PLAN-task-3 / PLAN-task-5 / PLAN-task-6 / PLAN-task-7 / PLAN-task-8 | Files Touched lists `Aidoku.xcodeproj/project.pbxproj` (orphan) — no step body modifies it. (Tasks 2 and 4 explicitly handle it in Step 6 / Step 4 respectively; the other five do not.) | Recipe preconditions not met: 0 steps mention basename. |
| 10 | Completeness | WARN | PLAN-task-7-sentence-translation.md / PLAN-task-8-vocab-flashcards.md | Files Touched lists `Shared/Localization/en.lproj/Localizable.strings` (orphan) — no step body modifies it. | Recipe preconditions not met: 0 steps mention basename. |
| 11 | Failure Pattern | WARN | PLAN-task-2-data-model.md | Step 1 verify command `xcodebuild -workspace Aidoku.xcodeproj -scheme Aidoku build` uses `-workspace` but `Aidoku.xcodeproj` is a project (no `.xcworkspace` in repo); should be `-project Aidoku.xcodeproj`. | No recipe covers incorrect flag rewriting; manual edit needed. |
| 12 | Failure Pattern | WARN | PLAN-task-1-ocr-validation-spike.md | Stale git state: `.gitignore` has uncommitted edits and Task 1 plans to MODIFY it. Commit or stash before `/execute`. | Workspace state, not a plan-content fix. |
| 13 | Assumption Stress-Test | INFO | PLAN-task-6-word-lookup-sheet.md | Decision #9 cites `ReaderPageView.swift:10` for `MarkdownView`; line 10 is `import MarkdownUI`. The local `MarkdownView` wrapper is at lines 27 and 464; defined at `iOS/UI/Reader/Page/MarkdownView.swift`. | Informational; intent is correct, only the line citation is approximate. |

## Summary

### Blockers (must fix before execution)
None.

### Warnings (should review)
1. **Task 8 dependency conflict** — Step 6's "Depends on: Task 6" contradicts frontmatter `parallelizable_with: [..., 6, ...]`. Move Task 6 into `depends_on` and out of `parallelizable_with`, or restructure Step 6 to not modify `WordLookupSheet.swift`.
2. **Cross-task `project.pbxproj` writes** — Five+ pairs of mutually-parallelizable tasks all modify `project.pbxproj`. Decide whether to serialize the project-file edits or batch them at the end of each phase.
3. **Cross-task `Localizable.strings` writes** — Six tasks modify it; mutual parallelism creates merge-conflict risk.
4. **Tasks 6/7 `ReaderViewController.swift`** — both subscribe to different `LearnerEvents`; either serialize the two tasks or pre-create a thin host coordinator that both write into.
5. **Task 2 Step 7 / Task 5 Step 7 missing Files Touched rows** — needs manual append (verb mapping ambiguous for recipe).
6. **Task 5 orphan `ReaderViewController.swift`** — Approach mentions a toolbar button but no step adds it; either add a step or drop the Files Touched entry.
7. **Task 2 Step 1 wrong xcodebuild flag** — change `-workspace Aidoku.xcodeproj` to `-project Aidoku.xcodeproj`.
8. **Tasks 3, 5, 6, 7, 8 `project.pbxproj` orphans** — no step explicitly handles the `pbxproj` edit; Tasks 2 and 4 do (Step 6 / Step 4). Either replicate the pattern or remove the row in favor of a cross-cutting "add files to target" convention.
9. **Tasks 3, 7, 8 `Localizable.strings` orphans** — same shape as above; no step modifies the listed file.
10. **Stale git state** — `.gitignore` has uncommitted edits; commit or stash before `/execute`.

### Info
1. Task 6 Decision #9 cites `ReaderPageView.swift:10` for `MarkdownView`; intent is correct, line citation is approximate (real wrapper at `:27`, defined in `iOS/UI/Reader/Page/MarkdownView.swift`).
