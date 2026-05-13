---
task: 2
task_name: "app-icon-swap"
status: completed
created: 2026-05-12
steps_total: 4
steps_completed: 4
estimated_files: 6
parallelizable_with: [1, 3, 4]
depends_on: []
---

## Goal

Replace the legacy raster `AppIcon.appiconset` from the asset drop at `~/Downloads/AppIcons/Assets.xcassets/AppIcon.appiconset/` and remove the now-stale Liquid Glass `AppIcon.icon/` so both iOS 17 and iOS 18+ display the new icon.

## Acceptance Criteria

- [ ] `Shared/Assets.xcassets/AppIcon.appiconset/Contents.json` is byte-identical to the drop (`diff -q ~/Downloads/AppIcons/Assets.xcassets/AppIcon.appiconset/Contents.json Shared/Assets.xcassets/AppIcon.appiconset/Contents.json` exits 0).
- [ ] Every PNG referenced in the new `Contents.json` exists in `Shared/Assets.xcassets/AppIcon.appiconset/` (`xcrun actool --validate Shared/Assets.xcassets --target-device iphone --target-device ipad --minimum-deployment-target 15.0 --platform iphoneos` reports no missing icons).
- [ ] `Shared/AppIcon.icon/` no longer exists (`test ! -e Shared/AppIcon.icon`).
- [ ] Asset catalog still resolves the `AppIcon` symbol — Xcode build emits no `AppIcon` warnings/errors and the built `.app/AppIcon60x60@2x.png` (or platform equivalent) exists.

## What This Is Not

- Not creating a new Liquid Glass `.icon` variant — the drop didn't include one; a follow-up task can ship a designer-provided one later.
- Not touching the unused `~/Downloads/AppIcons/android/` icons (project is iOS/macOS only).
- Not using `~/Downloads/AppIcons/appstore.png` or `playstore.png` — no app-store distribution planned.

## Approach

`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (`Aidoku.xcodeproj/project.pbxproj:3530, 3575, 3620`) resolves to whichever `AppIcon.{appiconset,icon}` Xcode finds. Currently `AppIcon.icon` (Liquid Glass) takes priority on iOS 18+ and `.appiconset` falls back on iOS 17. Removing `AppIcon.icon/` makes the raster set the only resolution on every OS — uniform iconography across deployment targets.

The drop contains a superset of icon sizes (37 PNGs incl. 1024px for App Store, plus 20/29/40/58/60/76/80/87/120/152/167/180 for iOS; non-iOS sizes go unused but cost nothing). Drop-in replacement is safe: `Contents.json` from the drop lists exactly the PNGs included.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Replace `AppIcon.appiconset` contents | Wholesale overwrite from drop | Drop is a superset of current sizes; safer than partial replace |
| 2 | Liquid Glass `AppIcon.icon/` | Delete | Agent recommendation (no Liquid Glass variant in drop; iOS 18+ visual mismatch otherwise unavoidable) |
| 3 | `ASSETCATALOG_COMPILER_APPICON_NAME` | Keep `AppIcon` | `AppIcon.appiconset` is still named `AppIcon`; no pbxproj change |
| 4 | Use drop's `Contents.json` as-is | Yes | Drop's manifest references exactly the PNGs it ships |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| DELETE | `Shared/Assets.xcassets/AppIcon.appiconset/{20,29,40,58,60,76,80,87,120,152,167,180}.png` | Replaced by drop |
| DELETE | `Shared/Assets.xcassets/AppIcon.appiconset/Icon.png` | Legacy 1024 file in drop is named `1024.png`; old `Icon.png` not in new manifest |
| DELETE | `Shared/Assets.xcassets/AppIcon.appiconset/Contents.json` | Replaced by drop's manifest |
| CREATE | `Shared/Assets.xcassets/AppIcon.appiconset/Contents.json` | Copied from drop |
| CREATE | `Shared/Assets.xcassets/AppIcon.appiconset/*.png` (37 files) | Copied from drop |
| DELETE | `Shared/AppIcon.icon/` (directory: `icon.json`, `Assets/`) | Remove Liquid Glass variant |

## Implementation Steps

- [ ] **Step 1: Verify drop integrity before touching repo**
  - **What:** Confirm the drop has `Contents.json` and the PNGs it references all exist.
  - **Files:** read-only against `~/Downloads/AppIcons/Assets.xcassets/AppIcon.appiconset/`
  - **Verify by:** `python3 -c "import json,os,sys; d='/Users/rutkay/Downloads/AppIcons/Assets.xcassets/AppIcon.appiconset'; m=json.load(open(d+'/Contents.json')); missing=[i['filename'] for i in m['images'] if 'filename' in i and not os.path.exists(d+'/'+i['filename'])]; sys.exit(1 if missing else 0); print(missing)"` exits 0.

- [ ] **Step 2: Replace `AppIcon.appiconset` contents**
  - **What:** `rm -rf Shared/Assets.xcassets/AppIcon.appiconset/*` then `cp -R ~/Downloads/AppIcons/Assets.xcassets/AppIcon.appiconset/. Shared/Assets.xcassets/AppIcon.appiconset/`.
  - **Files:** the asset dir
  - **Depends on:** Step 1
  - **Verify by:** `diff -rq ~/Downloads/AppIcons/Assets.xcassets/AppIcon.appiconset Shared/Assets.xcassets/AppIcon.appiconset` reports only directory-attribute differences (no file content differences).

- [ ] **Step 3: Delete `Shared/AppIcon.icon/`**
  - **What:** Remove the Liquid Glass icon folder so iOS 18+ falls back to the new raster set.
  - **Files:** `Shared/AppIcon.icon/`
  - **Verify by:** `test ! -e Shared/AppIcon.icon`.

- [ ] **Step 4: Build + asset validation**
  - **What:** Asset catalog compiles cleanly; built bundle contains the new app icon.
  - **Files:** read-only build verification against `Aidoku.xcodeproj` (or `Aidoku-lingo.xcodeproj` if Task 1 ran first)
  - **Verify by:** `xcodebuild -scheme "Aidoku (iOS)" -configuration Debug -destination "generic/platform=iOS" -project Aidoku.xcodeproj build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation 2>&1 | grep -iE 'error:|warning:.*AppIcon'` returns no hits. **Note:** if this task runs after Task 1, substitute `-project Aidoku-lingo.xcodeproj`; if run in parallel before Task 1's project rename, use `Aidoku.xcodeproj`.

## Testing Strategy

Visual smoke test: install build on a device or simulator (iOS 17 and iOS 18 if available), confirm the new icon shows on the home screen.

No unit tests apply — asset-catalog validation is the only programmatic check.

## Risks

- **Most complex part:** `Contents.json` schema differences between the drop and the existing manifest. The drop's manifest may reference filenames not currently in the set (covered) or use newer `appearances` keys that pre-Xcode-26 toolchains don't recognise. Mitigation: Step 2's `diff -rq` flags any deviation.
- **Most-likely-wrong assumption:** that the drop's `Contents.json` is well-formed. If it's malformed `actool` will fail loudly at Step 4 — easy to catch, easy to revert.
- **Edge case easy to miss:** if pbxproj has a stale `AppIcon` reference (e.g., an `INFOPLIST_KEY_NSStickerSharingLevel` or icon override), the build can still pick a legacy path. None observed in exploration, but Step 4's `grep` on build output catches it.
- **Parallel-execution conflict with Task 1:** both tasks touch `project.pbxproj`. Task 2 has no pbxproj edit (asset name unchanged), so the conflict is zero in practice. If a serialization is desired, run Task 1 first.
