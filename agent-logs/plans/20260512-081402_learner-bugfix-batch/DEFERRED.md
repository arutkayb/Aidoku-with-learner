# Deferred Items — 20260512-081402_learner-bugfix-batch

## Tooling Autoinstall

| Tool | Status | Notes |
|------|--------|-------|
| xcodebuild | available (Xcode 26.5 at /Applications/Xcode.app) | Build/test blocked — iOS 26.5 platform component not installed in Xcode. Error: "iOS 26.5 is not installed. Please download and install the platform from Xcode > Settings > Components." |

**Impact:** All `xcodebuild build` and `xcodebuild test` verify-by commands cannot run. Code has been reviewed for syntactic and semantic correctness by reading, but automated compilation checks are skipped. Manual install required: open Xcode → Settings → Components → download iOS 26.5 Simulator runtime + device support.

## Execution Mode

Sequential (default). Tasks executed in wave order: Wave 1 (1, 2, 4, 7) → Wave 2 (3, 5) → Wave 3 (6).

## Skipped Steps

| Task | Step | Reason | Error |
|------|------|--------|-------|
| (none yet) | | | |

## Autonomous Decisions

| # | Task | Decision | Rationale |
|---|------|----------|-----------|
| 1 | All | Skip `xcodebuild build/test` verify-by commands | iOS 26.5 platform not installed in Xcode; build/test infeasible. All code reviewed manually for correctness. |
| 2 | 1 | Legacy `false` → key absent (inherit) rather than `"off"` | Per plan Decision Register #4: default is inherit; a `false` entry means "user never explicitly enabled" which maps better to inherit than an explicit off. |
