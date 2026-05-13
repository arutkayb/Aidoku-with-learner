---
task: 5
task_name: "folder-and-repo-rename"
status: planned
created: 2026-05-12
steps_total: 6
steps_completed: 0
estimated_files: 1
parallelizable_with: []
depends_on: [1, 2, 3, 4]
---

## Goal

Land the destructive parts of the rebrand: rename the GitHub repo `arutkayb/Aidoku-with-learner` → `arutkayb/Aidoku-lingo`, repoint the local `origin` remote, delete the orphaned `altstore` branch on the remote, hand the user the local-folder `mv` command, then run a final integration build from the new layout.

## Acceptance Criteria

- [ ] `gh repo view arutkayb/Aidoku-lingo` succeeds (HTTP 200); `gh repo view arutkayb/Aidoku-with-learner` returns 404 (or redirects).
- [ ] `git remote get-url origin` outputs `git@github.com:arutkayb/Aidoku-lingo.git` (or the HTTPS equivalent if origin was HTTPS).
- [ ] `git ls-remote --heads origin altstore` returns no rows (branch deleted).
- [ ] Local working tree is at `/Users/rutkay/workspace/mangadict/Aidoku-lingo` (user has executed the `mv`). Verify by `pwd` from that location.
- [ ] `xcodebuild -scheme "Aidoku (iOS)" -configuration Debug -destination "generic/platform=iOS" -project Aidoku-lingo.xcodeproj build …` from the new path succeeds.
- [ ] `graphify update .` runs cleanly from the new path (graph refreshes to new project layout).

## What This Is Not

- Not deleting the GitHub repo and recreating it — `gh repo rename` preserves history, issues, releases, and the GitHub-suggested redirect from the old name.
- Not changing the default branch name.
- Not editing any files inside the working tree — those changes belong to Tasks 1-4.
- Not publishing a release.

## Approach

Three-phase sequence:

1. **GitHub side** (agent-runnable): `gh repo rename`, update local remote URL, delete the `altstore` branch on remote.
2. **Local-folder mv** (USER must run): Xcode holds file locks on the workspace and writes to DerivedData paths derived from the project path; renaming the parent dir under a running Xcode corrupts indexes. The agent prints the exact command and waits.
3. **Verification** (agent-runnable from the new path once the user confirms): build, graphify update.

The agent assumes Tasks 1-4 have been committed before reaching this task — folder-rename + remote-update during dirty working state is too easy to lose work in. If Task 1's xcodeproj rename hasn't been committed, the verification build will fail and Task 5 stops cleanly.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | New GitHub repo name | `Aidoku-lingo` | Matches GitHub convention; user-implied |
| 2 | Repo-rename tool | `gh repo rename` | Preserves history, issues, and stars; built-in redirect from old name |
| 3 | Origin URL update | Match prior protocol (SSH) | Current `git@github.com:arutkayb/...` form |
| 4 | `altstore` branch | Delete via `git push origin --delete` | User-confirmed (recommended by agent; no AltStore distribution) |
| 5 | Local-folder rename | USER runs `mv`, not agent | Xcode file-lock + DerivedData safety |
| 6 | Run order between Task 1 xcodeproj rename and Task 5 folder rename | Project rename first, folder rename last | Project rename is a `git mv` (recoverable); folder rename is OS-level (recoverable but invalidates IDE state) |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | `.git/config` (via `git remote set-url`) | `origin` URL repoints from `…/Aidoku-with-learner.git` to `…/Aidoku-lingo.git` |

No tracked files in the working tree are touched by this task — all surface changes are at the OS and remote level.

## Implementation Steps

- [ ] **Step 1: Verify clean working state + prior tasks committed**
  - **What:** `git status --porcelain` shows no unstaged content from Tasks 1-4. If anything is pending, stop and ask the user to commit first.
  - **Files:** read-only `git status` check; no files touched
  - **Verify by:** `git status --porcelain` returns empty.

- [ ] **Step 2: Rename the GitHub repo**
  - **What:** `gh repo rename Aidoku-lingo --repo arutkayb/Aidoku-with-learner --yes` (or, if currently inside the repo, `gh repo rename Aidoku-lingo --yes`). If the env-token-shadowing footgun appears, retry with `env -u GITHUB_TOKEN -u GH_TOKEN gh repo rename Aidoku-lingo --yes`.
  - **Files:** remote-only (GitHub repo metadata via `gh`); no local files touched
  - **Verify by:** `gh repo view arutkayb/Aidoku-lingo --json name -q .name` prints `Aidoku-lingo`.

- [ ] **Step 3: Repoint local origin remote**
  - **What:** `git remote set-url origin git@github.com:arutkayb/Aidoku-lingo.git`
  - **Files:** `.git/config` (via `git remote set-url`)
  - **Depends on:** Step 2
  - **Verify by:** `git remote get-url origin` prints the new URL; `git ls-remote origin HEAD` succeeds (auth still works).

- [ ] **Step 4: Delete the `altstore` branch from the remote**
  - **What:** `git push origin --delete altstore`
  - **Files:** remote-only (deletes a branch ref on `origin`); no local files touched
  - **Depends on:** Step 3
  - **Verify by:** `git ls-remote --heads origin altstore` returns no rows.

- [ ] **Step 5: USER ACTION — rename the parent directory**
  - **What:** Agent stops and prints:
    > "Close Xcode if open, then run from your shell: `mv /Users/rutkay/workspace/mangadict/Aidoku-with-learner /Users/rutkay/workspace/mangadict/Aidoku-lingo && cd /Users/rutkay/workspace/mangadict/Aidoku-lingo`. Reply when done."
  - **Files:** filesystem-level rename of the working-tree parent directory (`/Users/rutkay/workspace/mangadict/Aidoku-with-learner` → `…/Aidoku-lingo`); no tracked files modified
  - **Verify by:** After user confirms, `pwd` from the new path returns `/Users/rutkay/workspace/mangadict/Aidoku-lingo`. `git status` works from the new path (`.git/` survived the move intact).

- [ ] **Step 6: Final integration build + graph refresh**
  - **What:** From the new path, build the iOS scheme and refresh graphify.
  - **Files:** read-only build + graph refresh against `Aidoku-lingo.xcodeproj` from the new working directory; `graphify-out/` updated by `graphify update .`
  - **Depends on:** Step 5 (and Tasks 1-4 committed)
  - **Verify by:**
    - `xcodebuild -scheme "Aidoku (iOS)" -configuration Debug -destination "generic/platform=iOS" -project Aidoku-lingo.xcodeproj build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation` exits 0.
    - `graphify update .` exits 0.
    - `plutil -p $(find ~/Library/Developer/Xcode/DerivedData -name 'Aidoku-lingo.app' -type d -newer /tmp -print 2>/dev/null | head -1)/Info.plist | grep -E 'CFBundleDisplayName|CFBundleIdentifier|CFBundleURLSchemes'` reports `"Aidoku Lingo"`, `"app.aidoku.Aidoku-lingo"`, `aidoku-lingo` respectively.

## Testing Strategy

No code tests. Integration verification is the build + the Info.plist inspection in Step 6.

Smoke test the rebuilt `.app` in a simulator: home-screen icon, app label "Aidoku Lingo", About screen shows only Version/Build + new GitHub link.

## Risks

- **Most complex part:** Step 5's user handoff. If the user runs the `mv` while Xcode is open, derived-data indexes break and the next build is slow (recoverable but annoying — "clean build folder" fixes it). If `.git/` is mid-operation (e.g., rebase in progress), `mv` corrupts the operation. Mitigation: Step 1 verifies clean `git status`.
- **Most-likely-wrong assumption:** that `gh repo rename` works without re-auth. The user's `gh` keyring auth may need a fresh login on first command. Mitigation: Step 2 includes the env-token fallback already documented in global CLAUDE.md.
- **Edge case easy to miss:** sibling-package paths in `project.pbxproj:3786-3792` use `relativePath = ../AidokuRunner` and `../Wasm3`. These are relative to the new project path; as long as the user's `mv` keeps the parent dir `/Users/rutkay/workspace/mangadict/` intact, the relative paths still resolve. If the user instead moves the project to a different parent, the build breaks at link time. Mitigation: Step 5 instruction names the exact new path.
- **`altstore` branch may carry GitHub Pages config**: if the upstream Aidoku repo deployed Pages from the `altstore` branch, deleting it disables that deployment on the fork. Personal-use fork has no Pages site, so this is intended cleanup.
- **GitHub-side redirect**: `gh repo rename` leaves a redirect from `arutkayb/Aidoku-with-learner` → `arutkayb/Aidoku-lingo`, which means stale URLs (PR #1, PR #3) keep resolving. Future GitHub-search results may briefly show the old name in caches.
