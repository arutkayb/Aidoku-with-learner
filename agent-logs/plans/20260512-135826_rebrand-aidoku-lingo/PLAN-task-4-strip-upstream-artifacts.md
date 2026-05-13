---
task: 4
task_name: "strip-upstream-artifacts"
status: completed
created: 2026-05-12
steps_total: 5
steps_completed: 5
estimated_files: 10
parallelizable_with: [1, 2, 3]
depends_on: []
---

## Goal

Delete or rewrite every upstream-Aidoku artifact that doesn't belong in a personal-use fork: AltStore distribution pipeline, Ko-Fi funding pointer, upstream Discord links, upstream issue templates, and the upstream-maintainer links in the in-app About screen.

## Acceptance Criteria

- [ ] `.github/FUNDING.yml` no longer exists.
- [ ] `.github/workflows/update_altstore_source.yml` no longer exists.
- [ ] `.github/workflows/supporting/` no longer exists (recursive delete of the `altstore/` JSON and `update_altstore_json.py`).
- [ ] `.github/ISSUE_TEMPLATE/` no longer exists.
- [ ] `.github/workflows/nightly.yml` and `.github/workflows/lint.yml` are unchanged (still useful for the fork).
- [ ] `iOS/New/Views/Settings/SettingsAboutView.swift` `GITHUB_REPO` link points to `https://github.com/arutkayb/Aidoku-lingo`; the `DISCORD_SERVER` and `SUPPORT_VIA_KOFI` SettingView rows are removed (`grep -c 'DISCORD_SERVER\|SUPPORT_VIA_KOFI' iOS/New/Views/Settings/SettingsAboutView.swift` returns 0).
- [ ] `grep -rl 'discord.gg/kh2PYT8V8d\|discord.gg/9U8cC5Zk3s\|ko-fi.com/skittyblock' --include='*.swift' --include='*.yml' --include='*.json' .` returns no hits inside the working tree (excluding `agent-logs/`, `graphify-out/`, `build/`).
- [ ] `xcodebuild -scheme "Aidoku (iOS)" build …` still succeeds after the About-view edit.

## What This Is Not

- Not removing or rewriting `Shared/Localization/en.lproj/Localizable.strings` keys `DISCORD_SERVER` / `SUPPORT_VIA_KOFI` — they become dead strings but touching 40+ lproj files for two unused keys is high-churn no-value work; the keys remain harmless.
- Not removing the `altstore` *branch* on the GitHub remote — that's a Task 5 operation (needs remote auth).
- Not stripping references to "Aidoku" inside the `AidokuRunner` / `Wasm3` sibling packages — those are upstream libraries, not part of this repo.
- Not deleting the `.github/workflows/nightly.yml` build pipeline — fork still benefits from CI builds.

## Approach

Three categories of cleanup:

1. **GitHub repo plumbing**: delete `FUNDING.yml`, the AltStore workflow + its python script + JSON, and the issue templates (whose `config.yml` carries the upstream Discord link).
2. **In-app About screen** (`iOS/New/Views/Settings/SettingsAboutView.swift:33-46`): edit the `Section` block — replace the GitHub URL string, delete the two trailing `SettingView` rows for Discord and Ko-Fi.
3. **Branding strings inside source files**: spot-check shows file headers carry `//  SettingsAboutView.swift\n//  Aidoku\n//  Created by Skitty on …` — leave headers alone (not user-visible; rewriting them across hundreds of files would be churn-heavy and would muddy git history for the actual rebrand commits).

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | `.github/FUNDING.yml` | Delete | Points to skittyblock's Ko-Fi |
| 2 | AltStore workflow + supporting files | Delete | No AltStore distribution per user |
| 3 | `.github/ISSUE_TEMPLATE/` | Delete entire folder | Templates carry upstream Discord; personal project doesn't need formal templates |
| 4 | `.github/workflows/nightly.yml` | Keep | CI build for the fork itself is still useful |
| 5 | `.github/workflows/lint.yml` | Keep | SwiftLint on PRs; no upstream content |
| 6 | About screen Discord + Ko-Fi rows | Remove (not replace) | Agent decision — personal fork has no community surface |
| 7 | About screen GitHub link | Replace with fork URL | Agent decision |
| 8 | `Localizable.strings` `DISCORD_SERVER` / `SUPPORT_VIA_KOFI` keys | Leave dormant | Removing requires touching 40+ lproj files for no functional gain |
| 9 | File-header comments ("//  Aidoku") in `.swift` files | Leave unchanged | Not user-visible; rewriting all bloats the rename diff |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| DELETE | `.github/FUNDING.yml` | Upstream-maintainer Ko-Fi pointer |
| DELETE | `.github/workflows/update_altstore_source.yml` | AltStore deploy pipeline |
| DELETE | `.github/workflows/supporting/altstore/apps.json` | AltStore source manifest |
| DELETE | `.github/workflows/supporting/update_altstore_json.py` | AltStore JSON generator |
| DELETE | `.github/workflows/supporting/` (empty dir after the above) | Cleanup |
| DELETE | `.github/ISSUE_TEMPLATE/bug_report.yml` | Upstream issue template |
| DELETE | `.github/ISSUE_TEMPLATE/feature_request.yml` | Upstream issue template |
| DELETE | `.github/ISSUE_TEMPLATE/config.yml` | Carries upstream Discord link |
| DELETE | `.github/ISSUE_TEMPLATE/` (empty dir after the above) | Cleanup |
| MODIFY | `iOS/New/Views/Settings/SettingsAboutView.swift` | `Section` block (lines 33-46): replace `https://github.com/Aidoku/Aidoku` with `https://github.com/arutkayb/Aidoku-lingo`; delete the two SettingView rows for `DISCORD_SERVER` and `SUPPORT_VIA_KOFI` |

## Implementation Steps

- [x] **Step 1: Delete AltStore pipeline files**
  - **What:** Remove the workflow + its python script + the JSON source manifest. Confirm `.github/workflows/supporting/` is empty after, then remove it.
  - **Files:** `.github/workflows/update_altstore_source.yml`, `.github/workflows/supporting/altstore/apps.json`, `.github/workflows/supporting/update_altstore_json.py`, `.github/workflows/supporting/`
  - **Verify by:** `test ! -e .github/workflows/update_altstore_source.yml && test ! -e .github/workflows/supporting`.

- [x] **Step 2: Delete ISSUE_TEMPLATE folder**
  - **What:** `rm -rf .github/ISSUE_TEMPLATE`
  - **Files:** `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/feature_request.yml`, `.github/ISSUE_TEMPLATE/config.yml`, `.github/ISSUE_TEMPLATE/`
  - **Verify by:** `test ! -e .github/ISSUE_TEMPLATE`.

- [x] **Step 3: Delete `.github/FUNDING.yml`**
  - **What:** Single-file delete.
  - **Files:** `.github/FUNDING.yml`
  - **Verify by:** `test ! -e .github/FUNDING.yml`.

- [x] **Step 4: Edit `SettingsAboutView.swift`**
  - **What:** Inside the second `Section` block, change the `GITHUB_REPO` row's URL string from `"https://github.com/Aidoku/Aidoku"` to `"https://github.com/arutkayb/Aidoku-lingo"`. Delete the two `SettingView` blocks for `DISCORD_SERVER` and `SUPPORT_VIA_KOFI` (lines 38-45 of the current file).
  - **Files:** `iOS/New/Views/Settings/SettingsAboutView.swift`
  - **Verify by:** `grep -c 'DISCORD_SERVER\|SUPPORT_VIA_KOFI' iOS/New/Views/Settings/SettingsAboutView.swift` returns 0; `grep -c 'arutkayb/Aidoku-lingo' iOS/New/Views/Settings/SettingsAboutView.swift` returns 1.

- [x] **Step 5: Build verification**
  - **What:** Confirm the About-view edit compiles and no dangling references break the build.
  - **Files:** read-only build verification against `Aidoku.xcodeproj` (or `Aidoku-lingo.xcodeproj` if Task 1 ran first)
  - **Verify by:** `xcodebuild -scheme "Aidoku (iOS)" -configuration Debug -destination "generic/platform=iOS" build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation 2>&1 | grep -E 'error:'` returns no hits. (Use whatever the project file is named at execution time — `Aidoku.xcodeproj` or `Aidoku-lingo.xcodeproj` depending on Task 1's status.)

## Testing Strategy

No new tests. Build success is the integration check. Manual smoke test: open the About screen in a simulator build and confirm only Version + Build + GitHub-link rows show.

## Risks

- **Most complex part:** the `SettingsAboutView.swift` edit. The current `Section` block has three trailing `SettingView` rows; the edit must leave only the GitHub one. Easy to leave a trailing comma or break the `Section` closure.
- **Most-likely-wrong assumption:** that `SettingView` is the correct row component. Yes — confirmed in `iOS/New/Views/Settings/SettingsAboutView.swift:34-46`. No assumption issue.
- **Edge case easy to miss:** the unused `DISCORD_SERVER` / `SUPPORT_VIA_KOFI` `Localizable.strings` keys remain referenced by nothing — `swiftlint` may warn about unused localized keys. Not currently a blocking lint rule for this project (verify in `.swiftlint.yml`).
- **GitHub URL** uses the current origin owner `arutkayb`; if the user changes their GitHub handle later, this becomes stale. Acceptable — single string, easy to spot in future audit.
- **`Localizable.strings` cleanup deferral:** if a later README or About-screen redesign re-uses these keys, the dormant strings are an asset, not a liability.
