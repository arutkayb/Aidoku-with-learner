---
task: 3
task_name: "readme-rewrite"
status: completed
created: 2026-05-12
steps_total: 2
steps_completed: 2
estimated_files: 1
parallelizable_with: [1, 2, 4]
depends_on: []
---

## Goal

Rewrite `README.md` to frame the project as a personal-use fork of Aidoku focused on Japanese-learner features, document feature set + iOS-version limitations, give an explicit setup procedure including the two sibling-package clones (`AidokuRunner`, `Wasm3`), link to the upstream `Aidoku/Aidoku` repo, and remove upstream-only sections (TestFlight, AltStore, Contributing, Translations).

## Acceptance Criteria

- [ ] `README.md` opens with the new project title "Aidoku Lingo" (display name) and immediately flags it as a fork of `Aidoku/Aidoku`.
- [ ] Contains a `## Features` section listing both base Aidoku reader features and the learner additions (OCR overlay, dictionary lookup, sentence translation, vocab flashcards).
- [ ] Contains a `## Limitations` section that explicitly names iOS 18+ as the requirement for learner features (driven by Apple Translation framework) and iOS 15+ for the reader itself.
- [ ] Contains a `## Setup` section with explicit `git clone` commands for `AidokuRunner` and `Wasm3` as sibling directories at the same level as the repo (matching the `../AidokuRunner` and `../Wasm3` paths used in `Aidoku.xcodeproj/project.pbxproj:3786-3792`).
- [ ] Contains a `## How to use` section covering: opening a manga, enabling Learner mode, OCR overlay interaction, vocab flashcards.
- [ ] Contains a link to the upstream repo `https://github.com/Aidoku/Aidoku` near the top and an acknowledgement of the upstream maintainer (`Skittyblock`).
- [ ] Does NOT contain the following sections or strings (`grep -iE` returns no hits): `TestFlight`, `AltStore`, `Discord`, `Weblate`, `CLA`, `Contributing`.
- [ ] `markdownlint README.md` (or `npx markdownlint-cli2 README.md`) reports no errors. If markdownlint isn't installed locally, validate by visual render via `gh markdown-preview` or by checking that the file parses as CommonMark with no unclosed code fences.

## What This Is Not

- Not a marketing / web-page rewrite. The README is a developer-facing setup doc.
- Not documenting Aidoku's upstream wasm-source authoring — that lives in upstream docs; link out, don't duplicate.
- Not adding screenshots in this task (deferred — keeps the diff text-only).

## Approach

The new README has six sections in this order, all H2:

1. **Aidoku Lingo** (H1 title + one-paragraph elevator pitch + "Forked from [Aidoku/Aidoku]…" badge line)
2. **Features** (split into "Reader (inherited from Aidoku)" and "Learner mode (this fork)")
3. **Limitations** (iOS-version split; offline Translation requires iOS 18 + downloaded language pack; personal-use only — no App Store/TestFlight/AltStore distribution)
4. **Setup** (clone three repos as siblings; open the `.xcodeproj`; signing notes; build run)
5. **How to use** (reader + learner flows)
6. **Acknowledgements & license** (Skittyblock + Aidoku contributors; GPLv3 inherited)

The Setup section is the most critical — it states the directory layout the project expects (`../AidokuRunner`, `../Wasm3` per `Aidoku.xcodeproj/project.pbxproj:3786-3792`).

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | README title | "Aidoku Lingo" | Matches `CFBundleDisplayName` from Task 1 |
| 2 | Upstream link target | `https://github.com/Aidoku/Aidoku` | User-specified |
| 3 | Library-dep clone URLs | `https://github.com/Aidoku/AidokuRunner` and `https://github.com/Aidoku/Wasm3` | Assumed from upstream Aidoku GitHub org pattern; verify during execution by `curl -I` before committing |
| 4 | iOS limitation framing | "Reader: iOS 15+; Learner: iOS 18+" | Matches `IPHONEOS_DEPLOYMENT_TARGET = 15.0` (`project.pbxproj:3554`) + Apple Translation framework requirement |
| 5 | Sections to strip | TestFlight, AltStore, Manual Installation, Contributing, Translations | User-specified ("remove remnants") |
| 6 | Acknowledgements | Keep — credit Skittyblock + Aidoku contributors | License obligation + fork etiquette |
| 7 | License section | Reference inherited GPLv3 | LICENSE file is the source of truth; just link to it |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | `README.md` | Wholesale rewrite — 36-line upstream README replaced with ~80-line forked-project README per the section outline above |

## Implementation Steps

- [x] **Step 1: Verify library-dep repo URLs**
  - **What:** Confirm `https://github.com/Aidoku/AidokuRunner` and `https://github.com/Aidoku/Wasm3` both resolve (HTTP 200) before encoding them in the README.
  - **Files:** read-only network check
  - **Verify by:** `curl -sI -o /dev/null -w '%{http_code}\n' https://github.com/Aidoku/AidokuRunner https://github.com/Aidoku/Wasm3` prints `200` twice. If either returns 404, locate the correct upstream URL via `gh search repos Aidoku Wasm3` before continuing.

- [x] **Step 2: Write the new `README.md`**
  - **What:** Replace the file's contents with the six-section structure described in Approach. Each section satisfies the corresponding Acceptance Criterion. Setup section uses fenced code blocks with shell commands; Limitations uses a bullet list with the iOS-version split explicit.
  - **Files:** `README.md`
  - **Depends on:** Step 1
  - **Verify by:** All acceptance-criteria `grep` checks pass: `grep -iE 'testflight|altstore|weblate|cla|discord|contributing' README.md` returns no hits; `grep -c 'Aidoku/Aidoku' README.md` ≥ 1; `grep -c 'iOS 18' README.md` ≥ 1; `grep -c '../AidokuRunner\|AidokuRunner' README.md` ≥ 1; `grep -c '../Wasm3\|Wasm3' README.md` ≥ 1. Also covers AC8: run `npx markdownlint-cli2 README.md` (or `markdownlint README.md` if installed globally); if neither is available, fall back to verifying code-fence balance with `awk '/^```/{n++} END{exit n%2}' README.md` (exit 0 = balanced).

## Testing Strategy

No code tests — this is doc-only. Validation is by `grep` against the new file (Step 2's verify checks) plus a visual render check via GitHub preview after the eventual commit lands.

## Risks

- **Most complex part:** Setup section accuracy. The user has to clone the right repos to the right paths and have them resolve when Xcode opens the workspace. If the URLs assumed in Step 1 turn out to be wrong (e.g., `Aidoku/Wasm3` is actually `Aidoku/aidoku-wasm3` or similar), the README misleads. Step 1's `curl` check catches that before commit.
- **Most-likely-wrong assumption:** that learner mode is iOS 18 minimum and not iOS 17.4 (Translation framework streaming) or iOS 18.1 (offline downloads). If iOS 17.4 also works for some features, the README is overly restrictive. Mitigation: cite "Apple Translation framework" and link to Apple's docs rather than asserting an exact minor version.
- **Edge case easy to miss:** linking to upstream Aidoku's `aidoku.app` website — it might describe features (TestFlight) the fork lacks. Avoid linking the website; link only to the GitHub repo.
