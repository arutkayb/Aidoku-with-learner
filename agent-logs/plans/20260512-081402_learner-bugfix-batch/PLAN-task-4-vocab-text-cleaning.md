---
task: 4
task_name: "vocab-text-cleaning"
status: completed
created: 2026-05-12
steps_total: 4
steps_completed: 4
estimated_files: 4
parallelizable_with: [2, 3, 6, 7]
depends_on: []
---

## Goal

Strip leading/trailing punctuation (keeping in-word `-` and `'`) before normalizing a vocab lemma, so words saved from on-page taps no longer carry trailing `,`/`!`/`?` etc. New saves are deduplicated automatically by the existing CoreData unique constraint.

## Acceptance Criteria

- [ ] Tapping the word "Tür," on a page and adding it to vocab results in a `VocabularyEntry` with `lemma = "tür"` (no comma).
- [ ] Apostrophe-internal words like `it's` round-trip to `lemma = "it's"` (apostrophe preserved).
- [ ] Hyphen-internal words like `auto-mobile` round-trip to `lemma = "auto-mobile"` (hyphen preserved).
- [ ] Tapping "Tür," followed by "Tür." in the same session creates only ONE `VocabularyEntry` (existing unique constraint on `(language, lemma)` enforces dedup once both normalize to `"tür"`).
- [ ] Existing entries already saved with punctuation are NOT modified (per user Q3 answer "Leave existing alone").
- [ ] `WordLookupViewModelTests` and `VocabularyManagerTests` pass.

## What This Is Not

- No CoreData migration. No batch cleanup of existing rows. Old `tür,` stays as-is.
- No diacritic stripping. `Ü` stays `Ü` (then lowercases to `ü`); diacritic handling is Task 7.
- No change to translation behavior — DeepL still receives the original surface form before normalization.

## Approach

- The single source of normalization is `VocabularyEntryObject.normalize(_:)` at `Shared/Data/Database/Objects/VocabularyEntryObject.swift:36-38`. `LearnerStrings.normalizeLemma(_:)` (line 16) delegates to it. Every save path (`WordLookupViewModel.toggleVocab`, `WordLookupViewModel.loadTranslation` cache, `LearnerOverlayView.swift:121` badge lookup) calls one of these two. One change covers all callers.
- Implementation: strip Unicode punctuation + symbols from the leading and trailing edges only — interior characters untouched. This preserves in-word `-` and `'` automatically (since they only get stripped if they're at the very edge, e.g., `'word'` → `word`).
- Pattern: walk inward from both ends while the character is in `(CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines))`. Then `lowercased()`.
- Acceptable alternative considered: regex `^[\\p{P}\\p{S}\\s]+|[\\p{P}\\p{S}\\s]+$` — rejected because Swift's `Foundation` regex with Unicode property escapes is heavier than the inline two-pointer walk and offers no clarity benefit here.

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Punctuation rule | Strip Unicode punctuation + symbols from edges only; keep in-word | User answered Q2 |
| 2 | Where to apply | Inside `VocabularyEntryObject.normalize(_:)` | Single source of truth; all save/lookup paths route through it |
| 3 | Treatment of existing rows | Leave alone, no migration | User answered Q3 |
| 4 | Whitespace handling | Continue to trim whitespace; combine into one pass with punctuation strip | Existing behavior; the new pass is a strict superset |
| 5 | Order of operations | trim+strip first, then `lowercased()` | Matches existing order; lowercasing-then-trim could leave a stray combining mark, edge-case avoided |
| 6 | Punctuation set | `CharacterSet.punctuationCharacters.union(.symbols)` (Foundation built-in) | Covers all Unicode general categories P* and S*, which is exactly what the user described |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| MODIFY | Shared/Data/Database/Objects/VocabularyEntryObject.swift | Rewrite `static func normalize(_ lemma: String) -> String` (lines 34-38) to do edge-trim of punctuation + symbols + whitespace, then lowercased. Update the doc comment. |
| MODIFY | Shared/Learner/LearnerStrings.swift | Update the docstring on `normalizeLemma` (lines 11-18) to reflect the new rule (preserve in-word punctuation, strip edges). |
| MODIFY | AidokuTests/VocabularyManagerTests.swift (or wherever `normalize` is currently tested) | Add cases: `"Tür," → "tür"`, `"!!hello!!" → "hello"`, `"it's" → "it's"`, `"auto-mobile" → "auto-mobile"`, `" foo " → "foo"`, `"foo." → "foo"`, `"日本語、" → "日本語"`. |
| MODIFY | AidokuTests/WordLookupViewModelTests.swift | Add a test: a `WordTapEvent` with `surfaceForm: "Tür,"` produces `viewModel.lemma == "tür"`. |

## Implementation Steps

- [x] **Step 1: New normalize implementation**
  - **What:** replace the body of `VocabularyEntryObject.normalize(_:)`. Define `let edgeStrip = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespacesAndNewlines)`. Walk the string's Unicode scalars from both ends, dropping characters whose scalar is in `edgeStrip`. Return `String(scalars[start...end]).lowercased()`.
  - **Files:** `Shared/Data/Database/Objects/VocabularyEntryObject.swift`
  - **Verify by:** `xcodebuild test -only-testing:AidokuTests/VocabularyManagerTests` passes with the new cases.

- [x] **Step 2: Update LearnerStrings docstring**
  - **What:** the comment at `LearnerStrings.swift:14-15` says "Punctuation is preserved per Decision Register #6". Replace with: "Edge punctuation and symbols are stripped; in-word punctuation (hyphen, apostrophe) is preserved. See Task 4 plan."
  - **Files:** `Shared/Learner/LearnerStrings.swift`
  - **Verify by:** docstring matches the implementation.

- [x] **Step 3: Tests for normalize edge cases**
  - **What:** add the test cases listed in the Files Touched table to `VocabularyManagerTests.swift` (or `WordLookupViewModelTests` if `normalize` doesn't have its own test).
  - **Files:** `AidokuTests/VocabularyManagerTests.swift`, `AidokuTests/WordLookupViewModelTests.swift`
  - **Verify by:** all new cases pass.

- [x] **Step 4: Manual end-to-end smoke**
  - **What:** open a manga, tap "Tür," → add to vocab → confirm in the Vocabulary list it appears as "Tür," (surfaceForm preserved for display) with the secondary line `lemma = tür` (no comma). Tap "Tür." next, confirm only one entry exists.
  - **Files:** none
  - **Verify by:** the second add does NOT create a duplicate row in the Vocabulary list.

## Testing Strategy

- Pure-function tests on `VocabularyEntryObject.normalize` are sufficient; the unique-constraint dedup is already covered by `CoreDataManager+Vocabulary` integration tests.
- Run `xcodebuild test -only-testing:AidokuTests/VocabularyManagerTests -only-testing:AidokuTests/WordLookupViewModelTests`.

## Risks

- **Most complex:** Unicode scalar walk for surrogate-pair-containing scripts. Mitigation: iterate over `String.UnicodeScalarView` indices, not `String.Index`, to avoid composed-character traps. Test case: `"日本語、" → "日本語"` (Japanese punctuation `、` is U+3001, category Po).
- **Assumption most likely wrong:** that all save paths route through `normalize`. Mitigation: verified the call sites are `WordLookupViewModel.swift:39`, `LearnerOverlayView.swift:121,135`, `LearnerStrings.swift:17` — all of these delegate. No bypass paths exist.
- **Easy-to-miss edge case:** a word that is ENTIRELY punctuation (e.g., `!!`) — normalize returns empty string. The save path should reject empty lemmas. Add a guard in `WordLookupViewModel.toggleVocab` to no-op if `lemma.isEmpty`.
