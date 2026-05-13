---
task: 1
task_name: "app-identity-rename"
status: completed
created: 2026-05-12
steps_total: 7
steps_completed: 7
estimated_files: 11
parallelizable_with: [2, 3, 4]
depends_on: []
---

## Goal

Rename every user-visible app-identity surface from "Aidoku" to "Aidoku Lingo" (display) / "Aidoku-lingo" (identifiers) while leaving Swift module symbols, CoreData model, target names, and file-format UTIs untouched.

## Acceptance Criteria

- [ ] `xcodebuild -scheme "Aidoku (iOS)" -configuration Debug -destination "generic/platform=iOS" build` succeeds.
- [ ] Built `.app` bundle's `Info.plist` reports `CFBundleDisplayName = Aidoku Lingo` and `CFBundleIdentifier = app.aidoku.Aidoku-lingo` (`plutil -p build/.../Aidoku-lingo.app/Info.plist`).
- [ ] `grep -r 'aidoku://' iOS/Info.plist` returns no hits; `grep -r 'aidoku-lingo' iOS/Info.plist` returns the URL scheme entry.
- [ ] `find . -maxdepth 2 -name 'Aidoku.xcodeproj' -not -path './graphify-out/*'` returns nothing; `Aidoku-lingo.xcodeproj/` exists with valid scheme files (`xcodebuild -list -project Aidoku-lingo.xcodeproj` lists the iOS + macOS schemes).
- [ ] `grep -nE 'INFOPLIST_KEY_CFBundleDisplayName|PRODUCT_NAME[ =]|PRODUCT_BUNDLE_IDENTIFIER' Aidoku-lingo.xcodeproj/project.pbxproj` shows only "Aidoku Lingo" / "Aidoku-lingo" / "app.aidoku.Aidoku-lingo" values for the main app target build configs (test target and module-internal references unchanged).
- [ ] `Shared/Aidoku.xcdatamodeld`, `iOS/AppDelegate.swift`, `macOS/AidokuApp.swift`, target names ("Aidoku (iOS)", "Aidoku (macOS)", "AidokuTests"), and UTI declarations (`app.aidoku.Aidoku.aix`, `app.aidoku.Aidoku.aib`) remain untouched (`grep -c` confirms unchanged).

## What This Is Not

- Not renaming `Shared/Aidoku.xcdatamodeld` — would force a CoreData migration that risks user data.
- Not renaming `iOS/AppDelegate.swift` / `macOS/AidokuApp.swift` filenames or the `AidokuApp` struct — internal Swift symbols, not user-visible.
- Not renaming the `AidokuTests` target — test bundle is dev-only.
- Not changing `CFBundleDocumentTypes` strings ("Aidoku Source", "Aidoku Backup") or UTI identifiers `app.aidoku.Aidoku.aix` / `.aib` — these are file-format identifiers shared with the AidokuRunner library ecosystem.
- Not touching `AidokuRunner` / `Wasm3` sibling packages.

## Approach

The rename cuts at three surfaces: (a) xcconfig (`Shared/Aidoku.xcconfig:9-10` defines `APP_ID_PREFIX` / `APP_ID_SUFFIX` — authoritative for the macOS bundle id; iOS Debug/Release configs in `Aidoku.xcodeproj/project.pbxproj:3560, 3605` carry a hardcoded `PRODUCT_BUNDLE_IDENTIFIER` override that must also be patched to `"app.aidoku.Aidoku-lingo"` so AC2's iOS `CFBundleIdentifier` check passes), (b) pbxproj build settings (`INFOPLIST_KEY_CFBundleDisplayName`, `PRODUCT_NAME` per-target — `Aidoku.xcodeproj/project.pbxproj:3543, 3561` and the macOS counterparts), (c) `InfoPlist.strings` localized `CFBundleDisplayName` (`Shared/Localization/{en,ja}.lproj/InfoPlist.strings`).

The xcodeproj folder rename is a directory `mv` plus path edits inside the two `.xcscheme` files under `xcshareddata/xcschemes/` (each references `container:Aidoku.xcodeproj` and `BuildableName = "Aidoku.app"`).

Module name: `PRODUCT_NAME = Aidoku-lingo` causes Swift to mangle the module name to `Aidoku_lingo` (hyphens → underscores). `iOS/Info.plist:84` uses `$(PRODUCT_MODULE_NAME).SceneDelegate` which Xcode resolves at build time, so no source edits needed. No qualified `Aidoku.Type` references exist in the main app target (verified during exploration).

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Home-screen display name | "Aidoku Lingo" (space) | User answer |
| 2 | Bundle identifier | `app.aidoku.Aidoku-lingo` | User confirmed no need for backwards compat |
| 3 | URL scheme | `aidoku-lingo://` | User answer |
| 4 | PRODUCT_NAME / xcodeproj rename | Both rename to `Aidoku-lingo` | User answer |
| 5 | CoreData model | Keep `Aidoku.xcdatamodeld` | Renaming triggers migration; user data at risk |
| 6 | UTI identifiers (`app.aidoku.Aidoku.aix`/`.aib`) | Unchanged | File-format ids shared with AidokuRunner ecosystem |
| 7 | Target names ("Aidoku (iOS)" etc.) | Unchanged | Dev-only label; rename invasive in pbxproj |
| 8 | Swift symbol `AidokuApp` struct | Unchanged | Internal symbol, not user-visible |
| 9 | xcconfig file names | Rename to match new project | Convention; pbxproj path edits required either way |
| 10 | `ASSETCATALOG_COMPILER_APPICON_NAME` | Keep `AppIcon` | Logical asset name still resolves to `AppIcon.appiconset` after Task 2 |
| 11 | iOS `PRODUCT_BUNDLE_IDENTIFIER` pbxproj override (lines 3560/3605) | Patch in place to `"app.aidoku.Aidoku-lingo"` (Option A from VALIDATION.md) rather than delete the override | Minimum-change fix; preserves the existing override pattern that AidokuTests also uses; avoids build-system regression risk from deleting an established override. Decision made under "work without stopping for clarifying questions" instruction; revisit if a cleaner xcconfig-only setup is desired later. |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | `Shared/Aidoku.xcconfig` | `APP_ID_SUFFIX = Aidoku-lingo` (was `Aidoku`); header comment updated |
| RENAME | `Shared/Aidoku.xcconfig` → `Shared/Aidoku-lingo.xcconfig` | File name match |
| RENAME | `iOS/Aidoku-IOS.xcconfig` → `iOS/Aidoku-lingo-IOS.xcconfig` | File name match; `#include` line updated to `../Shared/Aidoku-lingo.xcconfig` |
| RENAME | `macOS/Aidoku-MACOS.xcconfig` → `macOS/Aidoku-lingo-MACOS.xcconfig` | File name match; `#include` line updated |
| MODIFY | `Aidoku.xcodeproj/project.pbxproj` | Per-target build configs: `INFOPLIST_KEY_CFBundleDisplayName = "Aidoku Lingo"` (lines 3543, 3588), `PRODUCT_NAME = "Aidoku-lingo"` for main app target only (lines 3561, 3606, 3642, 3677 — not the AidokuTests target at 3699, 3729), `PRODUCT_BUNDLE_IDENTIFIER = "app.aidoku.Aidoku-lingo"` for iOS app target only (lines 3560, 3605 — pbxproj override of xcconfig; macOS app target inherits from xcconfig, AidokuTests target at lines 3699/3729 keeps `app.aidoku.AidokuTests`); file-ref paths for renamed xcconfigs (lines 674, 675, 676) |
| MODIFY | `iOS/Info.plist` | `CFBundleURLSchemes` array: `aidoku` → `aidoku-lingo` (line 61) |
| MODIFY | `Shared/Localization/en.lproj/InfoPlist.strings` | `"CFBundleDisplayName" = "Aidoku Lingo";` |
| MODIFY | `Shared/Localization/ja.lproj/InfoPlist.strings` | `"CFBundleDisplayName" = "Aidoku Lingo";` |
| RENAME | `Aidoku.xcodeproj` → `Aidoku-lingo.xcodeproj` | Project directory rename |
| MODIFY | `Aidoku-lingo.xcodeproj/xcshareddata/xcschemes/Aidoku (iOS).xcscheme` | `ReferencedContainer = "container:Aidoku-lingo.xcodeproj"`, `BuildableName = "Aidoku-lingo.app"` (line 18-20 of original scheme) |
| MODIFY | `Aidoku-lingo.xcodeproj/xcshareddata/xcschemes/Aidoku (macOS).xcscheme` | Same updates as iOS scheme |

## Implementation Steps

### Phase A: source-of-truth identifiers

- [x] **Step 1: Update `Shared/Aidoku.xcconfig`**
  - **What:** `APP_ID_SUFFIX` changes from `Aidoku` to `Aidoku-lingo`. Header comment block updated.
  - **Files:** `Shared/Aidoku.xcconfig`
  - **Verify by:** `grep -n 'APP_ID_SUFFIX' Shared/Aidoku.xcconfig` shows `APP_ID_SUFFIX = Aidoku-lingo`.

- [x] **Step 2: Rename xcconfig files + fix `#include` lines**
  - **What:** `Shared/Aidoku.xcconfig` → `Shared/Aidoku-lingo.xcconfig`; `iOS/Aidoku-IOS.xcconfig` → `iOS/Aidoku-lingo-IOS.xcconfig` with `#include "../Shared/Aidoku-lingo.xcconfig"`; same for macOS. Update file-ref paths at `project.pbxproj:674-676` to match.
  - **Files:** all three xcconfigs; `Aidoku.xcodeproj/project.pbxproj`
  - **Depends on:** Step 1
  - **Verify by:** `ls Shared/Aidoku-lingo.xcconfig iOS/Aidoku-lingo-IOS.xcconfig macOS/Aidoku-lingo-MACOS.xcconfig` lists all three; `grep -nE 'xcconfig' Aidoku.xcodeproj/project.pbxproj | grep -v 'Aidoku-lingo'` returns no remaining old paths.

### Phase B: pbxproj build settings + Info.plist surfaces

- [x] **Step 3: Update per-target build configs in `project.pbxproj`**
  - **What:** For both Debug and Release configs of the iOS + macOS app targets: `INFOPLIST_KEY_CFBundleDisplayName = "Aidoku Lingo"` (was `Aidoku`) and `PRODUCT_NAME = "Aidoku-lingo"` (was `Aidoku`). Additionally, for the iOS app target only (Debug at line 3560, Release at 3605): `PRODUCT_BUNDLE_IDENTIFIER = "app.aidoku.Aidoku-lingo"` (was `"app.aidoku.Aidoku-with-learner"`) — these are hardcoded pbxproj overrides that win over the xcconfig-derived value; the macOS app target has no override and inherits from xcconfig. Test target build configs at lines 3699/3729 (`PRODUCT_BUNDLE_IDENTIFIER = app.aidoku.AidokuTests`) remain unchanged.
  - **Files:** `Aidoku.xcodeproj/project.pbxproj` (lines 3543, 3560, 3561, 3588, 3605, 3606, 3642, 3677 — verify exact lines pre-edit)
  - **Depends on:** Step 2
  - **Verify by:** `grep -nE 'INFOPLIST_KEY_CFBundleDisplayName|PRODUCT_NAME |PRODUCT_BUNDLE_IDENTIFIER' Aidoku.xcodeproj/project.pbxproj | grep -v -E 'Aidoku-lingo|AidokuTests|TARGET_NAME'` returns no hits.

- [x] **Step 4: Update `InfoPlist.strings`**
  - **What:** Replace `"CFBundleDisplayName" = "Aidoku";` with `"CFBundleDisplayName" = "Aidoku Lingo";` in en.lproj and ja.lproj.
  - **Files:** `Shared/Localization/en.lproj/InfoPlist.strings`, `Shared/Localization/ja.lproj/InfoPlist.strings`
  - **Verify by:** `grep -A0 CFBundleDisplayName Shared/Localization/*/InfoPlist.strings` shows `"Aidoku Lingo"` in both.

- [x] **Step 5: Change URL scheme in `iOS/Info.plist`**
  - **What:** `CFBundleURLSchemes` array entry `aidoku` → `aidoku-lingo`.
  - **Files:** `iOS/Info.plist`
  - **Verify by:** `plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw iOS/Info.plist` prints `aidoku-lingo`.

### Phase C: project directory rename

- [x] **Step 6: Rename `Aidoku.xcodeproj` → `Aidoku-lingo.xcodeproj` and update scheme refs**
  - **What:** `mv Aidoku.xcodeproj Aidoku-lingo.xcodeproj`. Inside both `.xcscheme` files under `xcshareddata/xcschemes/`, replace `container:Aidoku.xcodeproj` with `container:Aidoku-lingo.xcodeproj` and `BuildableName = "Aidoku.app"` with `BuildableName = "Aidoku-lingo.app"` (test bundle `AidokuTests.xctest` unchanged).
  - **Files:** project directory; both `.xcscheme` files
  - **Depends on:** Steps 1-5 committed (so a `git mv`-style rename is clean)
  - **Verify by:** `xcodebuild -list -project Aidoku-lingo.xcodeproj` lists schemes "Aidoku (iOS)" and "Aidoku (macOS)" with no errors.

### Phase D: build verification

- [x] **Step 7: Debug build for iOS**
  - **What:** Build succeeds; the built bundle's metadata reflects the new identity.
  - **Verify by:** `xcodebuild -scheme "Aidoku (iOS)" -configuration Debug -destination "generic/platform=iOS" -project Aidoku-lingo.xcodeproj build CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation` exits 0. Then `plutil -p $(find ~/Library/Developer/Xcode/DerivedData -name 'Aidoku-lingo.app' -type d | head -1)/Info.plist | grep -E 'CFBundleDisplayName|CFBundleIdentifier'` reports the new values.

## Testing Strategy

No new unit tests — this is config-only. Verification is by build success + `plutil` inspection of the built `.app` (Step 7 covers it).

`AidokuTests` target still builds against the renamed project (verify with `xcodebuild test -scheme "Aidoku (iOS)" ...` is out of scope here — Task 5 runs the integration build).

## Risks

- **Most complex part:** the pbxproj edits. The same key (`INFOPLIST_KEY_CFBundleDisplayName`, `PRODUCT_NAME`) appears in multiple build configs (Debug/Release × iOS/macOS × main/test). Test target lines must be left alone. Mistargeting risks breaking the test build. Mitigation: targeted line-anchored edits, then `grep` verification before commit.
- **Most-likely-wrong assumption:** that no code does qualified `Aidoku.X` module references. The main app target almost never does (Swift discourages it), but a stray case would surface as a compile error in Step 7.
- **Edge case easy to miss:** scheme files cache `BuildableIdentifier` GUIDs that should remain stable across the rename — do **not** regenerate them, only edit the human-readable `ReferencedContainer` and `BuildableName` strings.
- **macOS scheme + scheme `(macOS)`:** the same edits apply; easy to update only the iOS scheme and leave macOS broken.
- **`graphify update .`** should be run after the rename so the graph reflects the new project layout; this is a Task 5 follow-up.
