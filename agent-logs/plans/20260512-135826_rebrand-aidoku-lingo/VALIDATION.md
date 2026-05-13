# Plan Validation: 20260512-135826_rebrand-aidoku-lingo

**Date:** 2026-05-12
**Plans validated:** 5
**Overall:** FAIL

Overall semantics (post-fix): one escalate-only FAIL remains in Plan 1 (Approach assumption contradicted by pbxproj override; iOS `CFBundleIdentifier` acceptance criterion not achievable as written). All `estimated_files` mismatches were fix-mechanical and cleared.

## 1. Precondition Sweep

22/22 preconditions verified

- PASS: Plan 1 — `Shared/Aidoku.xcconfig`, `iOS/Aidoku-IOS.xcconfig`, `macOS/Aidoku-MACOS.xcconfig`, `Aidoku.xcodeproj/project.pbxproj`, `iOS/Info.plist`, `Shared/Localization/{en,ja}.lproj/InfoPlist.strings`, both `.xcscheme` files all exist on disk.
- PASS: Plan 2 — `Shared/Assets.xcassets/AppIcon.appiconset/` (14 existing files), `Shared/AppIcon.icon/` directory, and the drop at `~/Downloads/AppIcons/Assets.xcassets/AppIcon.appiconset/Contents.json` (+ 37 PNGs) all present.
- PASS: Plan 3 — `README.md` exists; no other CREATE files needed.
- PASS: Plan 4 — `.github/FUNDING.yml`, `.github/workflows/update_altstore_source.yml`, `.github/workflows/supporting/{altstore/apps.json,update_altstore_json.py}`, `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}.yml`, `iOS/New/Views/Settings/SettingsAboutView.swift` all exist.
- PASS: Plan 5 — `.git/config` operations target current `arutkayb/Aidoku-with-learner.git` remote (confirmed).
- INFO: Plan 1, Files Touched row for `Aidoku.xcodeproj/project.pbxproj` cites macOS `PRODUCT_NAME` lines `3642, 3677`; actual lines are `3643, 3678` (off-by-one). The plan's `Verify by` for Step 3 uses `grep`, not absolute line numbers, and the row itself flags "verify exact lines pre-edit" — execution will re-anchor. **Resolution: Info** (no edit needed).
- PASS: pattern/file references (`project.pbxproj:3786-3792` sibling-package paths, `iOS/Info.plist:84` SceneDelegate, `SettingsAboutView.swift:34-46` Section block) all verified present at cited locations.
- PASS: dependency references (`gh`, `git`, `xcodebuild`, `plutil`, `xcrun actool`, `graphify`) are all standard tooling; sibling packages `../AidokuRunner` and `../Wasm3` referenced at `project.pbxproj:3786-3792` (verified by grep).
- PASS: no environment-variable references in any plan (no `process.env`, no API keys).

## 2. Dependency Check

PASS (intra- and inter-task graphs are acyclic; no missing references; no implicit file conflicts trigger fix-mechanical recipes)

- PASS: Plan 1 — Step 1 → 2 → 3 → 6, Step 6 cites "Steps 1-5 committed"; no cycles. Step 7 (build verification) has no explicit `Depends on` but lists no shared Files with prior steps, so no fix-mechanical recipe triggers. **Resolution: Info** — logical dependency on Step 6 is implicit (verify command uses `Aidoku-lingo.xcodeproj`, which only exists post-rename).
- PASS: Plan 2 — Step 1 → 2; Steps 3, 4 have no explicit deps but no shared Files with Steps 1-2. **Resolution: Info** — Step 4 verifies asset-catalog compile, logically post-Steps-2-3.
- PASS: Plan 3 — Step 1 → 2; clean chain.
- PASS: Plan 4 — Steps 1, 2, 3, 4 are independent (no shared Files, no cycles); Step 5 (build) has no explicit dep but logically follows Step 4. **Resolution: Info** — escalate-only per recipe rules (no file conflict triggers fix-mechanical).
- PASS: Plan 5 — Step 2 → 3 → 4, Step 5 is USER-blocked, Step 6 → Step 5. Chain valid; consistency between `Depends on` fields verified.
- PASS: Inter-task — `parallelizable_with` and `depends_on` are mutually consistent; no task appears in both fields of another task; Task 5's `depends_on: [1, 2, 3, 4]` matches the four upstream plans; no cross-task file overlap (Tasks 1-4 touch disjoint file sets; Task 2's `xcodebuild` verify is verification-only, not modification).

## 3. Assumption Stress-Test

5/6 assumptions still hold

- **FAIL: Plan 1, Approach paragraph 1** — Claim: "`Shared/Aidoku.xcconfig:9-10` defines `APP_ID_PREFIX` / `APP_ID_SUFFIX` — the single source of truth for bundle id." Reality: `Aidoku.xcodeproj/project.pbxproj:3560` and `:3605` hardcode `PRODUCT_BUNDLE_IDENTIFIER = "app.aidoku.Aidoku-with-learner"` for the iOS Debug/Release configs, which overrides the xcconfig at build time. Acceptance Criterion 2 (`CFBundleIdentifier = app.aidoku.Aidoku-lingo`) cannot be met by editing only the xcconfig + the build-setting subset listed in Step 3. **Resolution: Escalated** (re-planning needed — see Escalations table).
- PASS: Plan 1 Decision Register #1 (display name "Aidoku Lingo"), #2 (bundle id choice), #3 (URL scheme), #4 (PRODUCT_NAME rename), #5 (keep `Aidoku.xcdatamodeld`), #10 (`ASSETCATALOG_COMPILER_APPICON_NAME` stays `AppIcon`) — all verified against codebase state (xcconfig contents, pbxproj entries, asset catalog directory).
- PASS: Plan 2 Decision Register #1-4 — the drop manifest exists, `AppIcon.appiconset` already exists, `AppIcon.icon/` is present.
- PASS: Plan 3 Decision Register #4 (iOS 15.0 deployment target) — verified at `project.pbxproj:3554` (`IPHONEOS_DEPLOYMENT_TARGET = 15.0`).
- INFO: Plan 3 Decision Register #3 — library-dep clone URLs (`Aidoku/AidokuRunner`, `Aidoku/Wasm3`) are external GitHub URLs; cannot verify without a network call. Step 1 of Plan 3 includes a `curl -I` pre-flight which handles this. **Resolution: Info**.
- PASS: Plan 4 Decision Register #6-7 (About-screen edits) — `iOS/New/Views/Settings/SettingsAboutView.swift:33-46` confirms the Section block layout matches the plan.
- PASS: Plan 5 Decision Register #6 — Tasks 1's xcodeproj rename is sequenced before Task 5's folder rename via the `depends_on: [1, 2, 3, 4]` frontmatter.
- INFO: Stale plan detection — plans created today (2026-05-12); no commits since. **Resolution: Info**.

## 4. Completeness Check

- PASS: Plan 1 — every Acceptance Criterion (AC1 build, AC3 URL scheme, AC4 project rename, AC5 pbxproj settings, AC6 unchanged items) maps to a step **except** AC2 (`CFBundleIdentifier`), which fails the Assumption Stress-Test (already escalated above; not double-counted here).
- WARN: Plan 2, Step 4 has no **Files** field. Step is "Build + asset validation" — pure verification, no file edits. **Resolution: Escalated** (escalate-only per recipe; intent is clear but field is empty).
- WARN: Plan 3, AC8 (`markdownlint README.md` reports no errors) is not directly verified by Step 2's `grep` checks; Step 2's `Verify by` covers AC1, AC2, AC4, AC5, AC6, AC7 but not the markdownlint pass. **Resolution: Escalated** (escalate-only — adding a verification command is a planning decision).
- WARN: Plan 4, Step 3 has no **Files** field; Step 1 and Step 2 use vague phrases ("as listed in DELETE rows above for AltStore"; "the folder + its three .yml files") instead of explicit paths. **Resolution: Escalated** (escalate-only ×3).
- WARN: Plan 4, Step 5 has no **Files** field (build verification). **Resolution: Escalated**.
- WARN: Plan 5, Steps 1, 2, 4, 5, 6 have no **Files** field; Step 3 should reference `.git/config`. **Resolution: Escalated** (escalate-only — these are operational steps on git/gh/filesystem rather than source-file edits; intent is clear from `What` text).
- WARN: Plan 1, frontmatter `estimated_files: 12` but Files Touched table has 11 rows. **Resolution: Fixed** (reconcile to 11).
- WARN: Plan 2, frontmatter `estimated_files: 14` but Files Touched table has 6 rows. **Resolution: Fixed** (reconcile to 6).
- WARN: Plan 4, frontmatter `estimated_files: 9` but Files Touched table has 10 rows. **Resolution: Fixed** (reconcile to 10).
- WARN: Plan 5, frontmatter `estimated_files: 0` but Files Touched table has 1 row. **Resolution: Fixed** (reconcile to 1).
- PASS: all `steps_total` frontmatter values match actual step count (1: 7=7; 2: 4=4; 3: 2=2; 4: 5=5; 5: 6=6).
- PASS: Files Touched orphan check — every Files Touched entry has at least one step referencing it (via path or basename).
- PASS: Testing Strategy — all plans declare appropriate test posture (no unit tests; build + grep + `plutil` inspection); test commands are concrete (`xcodebuild …` with full flags).

## 5. Failure Pattern Pre-Screen

- PASS: oversized steps — no step touches >5 files in its `Files` field. Plan 2 Step 2's `rm -rf + cp -R` acts on a directory (single logical operation, not enumerated files).
- PASS: vague verification — every `Verify by` field contains a runnable command (`xcodebuild`, `plutil`, `grep`, `diff`, `test`, `git ls-remote`).
- PASS: weak decision rationales — no "TBD" / unresolved entries. Plan 3 Decision #3 ("Assumed from upstream Aidoku GitHub org pattern; verify during execution by `curl -I`") couples a weak assumption to a Step 1 pre-flight check.
- INFO: stale git state — `bash check-git-state.sh` reports `INFO|4 uncommitted file(s) outside planning artifacts, none overlap with plan. No conflict.` **Resolution: Info**.
- PASS: import/dependency gaps (CREATE actions) — Plan 2's CREATE entries (37 PNGs + Contents.json) all come from the same source drop, no inter-step CREATE ordering issue. Plan 3's README rewrite is self-contained.

## Auto-fixes Applied

| # | Check | Plan file | Edit | Cleared? |
|---|-------|-----------|------|----------|
| 1 | Completeness (Frontmatter consistency) | PLAN-task-1-app-identity-rename.md | `estimated_files: 12` → `11` (matches 11 Files Touched rows) | yes |
| 2 | Completeness (Frontmatter consistency) | PLAN-task-2-app-icon-swap.md | `estimated_files: 14` → `6` (matches 6 Files Touched rows) | yes |
| 3 | Completeness (Frontmatter consistency) | PLAN-task-4-strip-upstream-artifacts.md | `estimated_files: 9` → `10` (matches 10 Files Touched rows) | yes |
| 4 | Completeness (Frontmatter consistency) | PLAN-task-5-folder-and-repo-rename.md | `estimated_files: 0` → `1` (matches 1 Files Touched row) | yes |

## Escalations (require human / re-plan)

| # | Check | Severity | Plan file | Finding | Why not auto-fixed |
|---|-------|----------|-----------|---------|--------------------|
| 1 | Assumption Stress-Test | FAIL | PLAN-task-1-app-identity-rename.md | Approach paragraph 1 claims `Shared/Aidoku.xcconfig` is "the single source of truth for bundle id," but `project.pbxproj:3560` and `:3605` hardcode `PRODUCT_BUNDLE_IDENTIFIER = "app.aidoku.Aidoku-with-learner"` for iOS Debug/Release, which overrides xcconfig at build time. AC2 (`CFBundleIdentifier = app.aidoku.Aidoku-lingo`) is unreachable without an extra pbxproj edit. | escalate-only — needs Step 3 (or new step) to also update lines 3560/3605 to `"app.aidoku.Aidoku-lingo"`, plus a Files Touched note. Planning decision. |
| 2 | Completeness (Step-to-file mapping) | WARN | PLAN-task-2-app-icon-swap.md | Step 4 has no `Files` field (build verification). | escalate-only |
| 3 | Completeness (Acceptance criteria coverage) | WARN | PLAN-task-3-readme-rewrite.md | AC8 (`markdownlint README.md` reports no errors) is not in Step 2's `Verify by`. | escalate-only — verify-command addition is a planning decision |
| 4 | Completeness (Step-to-file mapping) | WARN | PLAN-task-4-strip-upstream-artifacts.md | Step 1 `Files` is vague ("as listed in DELETE rows above for AltStore"). | escalate-only |
| 5 | Completeness (Step-to-file mapping) | WARN | PLAN-task-4-strip-upstream-artifacts.md | Step 2 `Files` is vague ("the folder + its three .yml files"). | escalate-only |
| 6 | Completeness (Step-to-file mapping) | WARN | PLAN-task-4-strip-upstream-artifacts.md | Step 3 has no `Files` field (single-file delete). | escalate-only |
| 7 | Completeness (Step-to-file mapping) | WARN | PLAN-task-4-strip-upstream-artifacts.md | Step 5 has no `Files` field (build verification). | escalate-only |
| 8 | Completeness (Step-to-file mapping) | WARN | PLAN-task-5-folder-and-repo-rename.md | Steps 1, 2, 4, 5, 6 have no `Files` field; Step 3 should list `.git/config`. | escalate-only — operational (git/gh/mv) steps; field semantics ambiguous |

## Summary

### Blockers (must fix before execution)

1. **Plan 1, Approach + Step 3 + AC2** — The pbxproj override of `PRODUCT_BUNDLE_IDENTIFIER` for iOS Debug/Release (`project.pbxproj:3560, 3605` — value `"app.aidoku.Aidoku-with-learner"`) is not addressed by the plan. As written, Step 3 only touches `INFOPLIST_KEY_CFBundleDisplayName` and `PRODUCT_NAME`, so the built iOS bundle would retain the old identifier. Re-planning options:
   - **Option A (simpler):** Add an extra edit in Step 3 (or a Step 3.5) to change lines 3560 and 3605 to `"app.aidoku.Aidoku-lingo"`; update the Files Touched row for `project.pbxproj`; update the Approach paragraph to drop the "single source of truth" framing.
   - **Option B (cleaner):** Delete lines 3560 and 3605 entirely so the xcconfig-derived `PRODUCT_BUNDLE_IDENTIFIER = $(APP_ID_PREFIX).$(APP_ID_SUFFIX)` becomes authoritative. Verify the AidokuTests target (lines 3699, 3729) keeps its own identifier `app.aidoku.AidokuTests` since Plan 1's "What This Is Not" preserves the test target.

### Warnings (should review)

1. Plan 2 Step 4, Plan 4 Steps 1/2/3/5, Plan 5 Steps 1/2/3/4/5/6: missing or vague `Files` fields. Operational/verification steps — intent is clear from `What`, but explicit fields would tighten step-to-file mapping for `/execute`.
2. Plan 3 AC8 (`markdownlint`) not directly verified by Step 2's `grep` checks. Consider adding the markdownlint command to Step 2's `Verify by`, or downgrade AC8 to optional.

### Info

1. Plan 1 Files Touched row for `Aidoku.xcodeproj/project.pbxproj` cites macOS `PRODUCT_NAME` lines `3642, 3677`; actual lines are `3643, 3678`. The plan's `Verify by` for Step 3 uses `grep`, so execution will re-anchor — non-blocking.
2. Plan 1 Step 7, Plan 2 Step 4, Plan 4 Step 5: implicit logical dependencies on prior steps (build verification follows file edits). No file conflicts, so no fix-mechanical recipe applies.
3. Plan 3 Decision #3: library-dep clone URLs are external; cannot verify offline. Plan 3 Step 1's `curl -I` pre-flight already handles this.
4. `check-git-state.sh` reports `INFO|4 uncommitted file(s) outside planning artifacts, none overlap with plan. No conflict.` Working tree state is acceptable.

## Resolution

**Date:** 2026-05-12
**Resolver:** /tackle-validation
**Outcome:** GREEN

| # | Finding (short) | Status | Plan file | Edit summary / Decision |
|---|-----------------|--------|-----------|-------------------------|
| 1 | Plan 1 — pbxproj override of iOS `PRODUCT_BUNDLE_IDENTIFIER` blocks AC2 | Resolved-by-judgment | PLAN-task-1-app-identity-rename.md | **Option A chosen** (patch in place). Approach paragraph (a) rewritten to acknowledge the iOS pbxproj override; Step 3's `What` extended to also set `PRODUCT_BUNDLE_IDENTIFIER = "app.aidoku.Aidoku-lingo"` at lines 3560 (iOS Debug) and 3605 (iOS Release); Step 3 `Files` adds those line numbers; Step 3 `Verify by` extends the grep to include `PRODUCT_BUNDLE_IDENTIFIER` and excludes `AidokuTests`; Files Touched row for `project.pbxproj` documents the override scope; new Decision Register row #11 records the Option A choice + rationale (min-change, preserves AidokuTests isolation, avoids regression risk from deleting an established override). Decision made per in-effect "work without stopping for clarifying questions" instruction. |
| 2 | Plan 2 Step 4 missing `Files` field | Fixed | PLAN-task-2-app-icon-swap.md | Added `Files: read-only build verification against Aidoku.xcodeproj (or Aidoku-lingo.xcodeproj if Task 1 ran first)`. |
| 3 | Plan 3 AC8 (markdownlint) not in Step 2 `Verify by` | Fixed | PLAN-task-3-readme-rewrite.md | Step 2 `Verify by` extended with `npx markdownlint-cli2 README.md` (or global `markdownlint`) plus an `awk` code-fence balance fallback when neither linter is installed — matches AC8's stated commands. |
| 4 | Plan 4 Step 1 `Files` vague | Fixed | PLAN-task-4-strip-upstream-artifacts.md | Replaced "as listed in DELETE rows above for AltStore" with the four explicit paths (`update_altstore_source.yml`, `apps.json`, `update_altstore_json.py`, `supporting/`). |
| 5 | Plan 4 Step 2 `Files` vague | Fixed | PLAN-task-4-strip-upstream-artifacts.md | Replaced "the folder + its three .yml files" with the four explicit paths (`bug_report.yml`, `feature_request.yml`, `config.yml`, `ISSUE_TEMPLATE/`). |
| 6 | Plan 4 Step 3 missing `Files` | Fixed | PLAN-task-4-strip-upstream-artifacts.md | Added `Files: .github/FUNDING.yml`. |
| 7 | Plan 4 Step 5 missing `Files` | Fixed | PLAN-task-4-strip-upstream-artifacts.md | Added `Files: read-only build verification against Aidoku.xcodeproj (or Aidoku-lingo.xcodeproj if Task 1 ran first)`. |
| 8 | Plan 5 Steps 1-6 missing/incomplete `Files` | Fixed | PLAN-task-5-folder-and-repo-rename.md | Each step now declares its surface: Step 1 read-only `git status`; Step 2 remote-only via `gh`; Step 3 `.git/config` (via `git remote set-url`); Step 4 remote-only branch delete; Step 5 filesystem rename of working-tree parent dir; Step 6 read-only build + `graphify-out/` refresh. |

`execution-state.json` was inspected; all five task entries' `depends_on` / `parallelizable_with` / `name` / `plan_file` fields already match plan frontmatter — no sync edit needed.
