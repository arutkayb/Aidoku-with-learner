# Deferred Items — 20260509-123140_mangadict-mvp

## Execution Mode

| Item | Decision | Reason |
|------|----------|--------|
| Sequential mode chosen | Tasks 2/3/4 are marked parallelizable_with each other but all modify `Aidoku.xcodeproj/project.pbxproj` → merge conflict risk if run in parallel. Similarly 6/7 and 5/6/7/8. Sequential mode eliminates all conflict risk. | Re-run with parallel mode is possible if maintainer prefers faster execution and accepts manual conflict resolution. |

## Tooling Autoinstall

| Binary | Status |
|--------|--------|
| xcodebuild | pre-installed (Xcode) |
| swift | pre-installed (Xcode) |

No quality packs detected (iOS/Swift project — pack system does not have an iOS-specific pack; Check 9 and Check 10 will be INCONCLUSIVE).

## Skipped Steps

| Task | Step | Reason | What Maintainer Needs To Do |
|------|------|--------|-----------------------------|
| 1 | Step 5: Run spike on all test images | Visual validation — requires real manga PNGs; `TestImages/` is empty | Drop 5–10 German manga page PNGs into `spikes/OCRSpike/OCRSpike/TestImages/`, rebuild app, run on simulator/device, fill in `SPIKE_NOTES.md` per-page accuracy rows |
| 1 | Step 6: Write go/no-go decision | Requires maintainer judgment after running spike | Write `GO` or `NO-GO` line at bottom of `spikes/OCRSpike/SPIKE_NOTES.md` with rationale; `grep -E '^(GO\|NO-GO)' spikes/OCRSpike/SPIKE_NOTES.md` should return one line |

## Validation Warnings Acknowledged (carry-forward)

| # | Warning | Disposition |
|---|---------|-------------|
| W1 | Task 8 dep conflict: Step 6 "Depends on: Task 6" vs frontmatter `parallelizable_with: [5,6,7]` | Resolved in state file: Task 8 `depends_on` set to [2,3,6] (moved 6 from parallelizable_with to depends_on); 5 removed since Task 8 does not actually modify Task-5-only files |
| W2 | Cross-task project.pbxproj writes | Handled by sequential execution |
| W3 | Task 2 Step 1 wrong xcodebuild flag | Will use `-project Aidoku.xcodeproj` instead of `-workspace` in verification commands |
| W4 | Stale git state (.gitignore uncommitted) | Task 1 modifies .gitignore — will commit the pre-existing change as part of Task 1 Step 1 |
| W5 | Task 2 Step 7 / Task 5 Step 7 missing Files Touched rows | Acknowledged; files will be modified per step body intent |
| W6 | Task 5 orphan ReaderViewController.swift | Will add toolbar button as planned in step body (Decision #10) |
| W7 | project.pbxproj orphans (Tasks 3/5/6/7/8) | Will add files to target in each task's final step |
| W8 | Localizable.strings orphans (Tasks 3/7/8) | Will add strings in each task's relevant step |
