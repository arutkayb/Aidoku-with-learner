---
title: Mangadict MVP — Manga Language Learner on Aidoku Fork
status: planned
created: 2026-05-09
type: PRD
source_doc: ../../../../manga-learner-vision-personal-20260508-201804.md
---

# Mangadict MVP

## One-line summary

Personal-use Aidoku fork that adds OCR + tap-to-translate + vocab list + minimal flashcards while reading German manga on iPad — fully on-device, no accounts, no sync.

## Why

Maintainer is learning German by reading manga. Existing tools (Mokuro, Yomitan, Migaku, LingQ) are desktop/browser-first, Japanese-first, or non-manga. Nothing solves "iPad on the couch, German manga, tap-to-translate, build a vocab list."

## Acceptance Criteria (product-level)

- [ ] On a German manga page in the reader with Learner mode on, every recognized word has an invisible tappable region.
- [ ] Tapping a recognized word opens a bottom sheet that shows the word, its translation, an "Add to vocab" button, and (if the word is in vocab) familiarity controls.
- [ ] A long-press or "Translate page" button groups detected text fragments into sentences and shows simplified translations for each sentence.
- [ ] Words added to the vocab list show a familiarity badge over their bounding box on subsequent pages.
- [ ] A Vocabulary tab lists all vocab entries grouped by familiarity level, sortable by date added.
- [ ] A Flashcards mode reviews vocab words; "Got it" raises the word's familiarity level by 1; "Done" locks at level 3 and removes it from the review queue.
- [ ] All data (vocab list, familiarity, flashcard state, OCR cache) lives on-device in Core Data; no network requests for translation by default (Apple Foundation Models on-device).
- [ ] Optional BYO DeepL API key in settings overrides the on-device translation for word and sentence lookups.
- [ ] All vocab/familiarity entries are included in the existing Aidoku backup/restore round-trip.
- [ ] OCR validation spike (Task 1) returns a "go/no-go" result before any Aidoku integration code is written.

## Scope (in)

- Paged reader mode only (the most common manga reader). Webtoon mode deferred.
- German (`de-DE`) as the configurable default OCR + source language. Other languages are settable but unvalidated in MVP.
- iOS/iPadOS only. iOS 26+ (Foundation Models requirement).
- 3-level familiarity, no time-based decay, no due-date scheduling.
- On-device OCR (Apple `VNRecognizeTextRequest`), on-device translation (Apple Foundation Models), with DeepL BYO key as override.

## Scope (out — explicitly)

- Webtoon / vertical-scroll OCR overlay (deferred — render geometry differs).
- Anki export, Anki bridging.
- Time-based SRS scheduling, decay, due-date queues.
- Passive familiarity (raised by mere in-context exposure rather than flashcards).
- Public distribution (App Store, AltStore, TrollStore). Personal Xcode signing only.
- Cloud sync of vocab list across devices.
- Multi-language quality tiering UI.
- Android, web, macOS targets.
- Reader feature work beyond the Learner integration points.

## Architecture overview

| Layer | Tech | Location |
|---|---|---|
| OCR | Apple Vision (`VNRecognizeTextRequest`, `.accurate`, `de-DE`) | `Shared/Learner/OCR/` |
| Translation | Apple Foundation Models (iOS 26+) on-device, DeepL BYO key fallback | `Shared/Learner/Translation/` |
| Sentence grouping | LLM-prompted via Foundation Models | `Shared/Learner/Translation/SentenceGrouper.swift` |
| Persistence | Core Data (existing `Aidoku.xcdatamodeld`) — new entities | `Shared/Data/Database/Objects/Vocabulary*.swift` |
| Reader integration | `ReaderPageView` + `ReaderPagedViewController` hooks | `iOS/UI/Reader/Page/`, `iOS/UI/Reader/Readers/Paged/` |
| Learner UI | New SwiftUI views | `iOS/UI/Learner/` |
| Settings keys | `UserDefaults` with `Learner.*` namespace | follows `Reader.upscaleImages` convention |

## Module isolation strategy

Per the vision doc's mitigation for Aidoku upstream churn, all new code lives under clearly-separated paths:
- `Shared/Learner/**` — services, models, glue
- `iOS/UI/Learner/**` — Learner-specific views
- `Shared/Data/Database/Objects/Vocabulary*.swift` etc. — new entity classes

Edits to existing Aidoku files are minimized to additive hooks:
- `ReaderPageView.swift` — one new method call per `setPage()` to forward image to `LearnerOverlayCoordinator`.
- `ReaderPagedViewController.swift` — one new call from `didFinishAnimating` to refresh learner state on page change.
- `ReaderViewController.swift` — one new toolbar button + per-manga setting key.
- `ReaderSettingsView.swift` — new "Learner" section with toggles.
- `BackupManager.swift` — new array fields in the `Backup` struct.
- `Aidoku.xcdatamodeld` — new entity definitions.

## Task decomposition

| # | Task | Depends On | Parallel With |
|---|------|-----------|---------------|
| 1 | OCR validation spike (kill switch) | — | — |
| 2 | Core Data + backup models | 1 | 3, 4 |
| 3 | Translation service (Foundation Models + DeepL fallback) | 1 | 2, 4 |
| 4 | OCR service | 1 | 2, 3 |
| 5 | Reader Learner mode + overlay | 1, 4 | 6 (after 5 starts), 7 (after 5 starts) |
| 6 | Word lookup bottom sheet | 2, 3, 5 | 7 |
| 7 | Sentence translation flow | 2, 3, 5 | 6, 8 |
| 8 | Vocab list + flashcards | 2, 3 | 5, 6, 7 |

Critical path: 1 → 4 → 5 → 6 → ship.

Task 1 is a hard gate: if OCR quality is insufficient, tasks 2-8 do not start.

## Out-of-scope from Q&A (lock these)

- No Anki integration in MVP.
- No iCloud sync of vocab/familiarity state in MVP (Core Data store is local-only for these entities; backup/restore covers device migration).
- No translation provider chooser UI beyond a single DeepL API key field. Google Translate, Azure, etc. deferred.
- No multi-image OCR queue or background prefetch in MVP — OCR runs lazily when a page becomes visible and Learner mode is on.
- No vocab list editing (rename / merge entries) in MVP.

## Open questions resolved (or defaulted in auto mode)

| Question | Resolution | Source |
|---|---|---|
| OCR engine | Apple Vision `VNRecognizeTextRequest`, `.accurate` level, `de-DE` hint | Vision doc |
| Translation engine | Apple Foundation Models on-device | Vision doc |
| BYO API provider | DeepL (single field) | Default — best German quality |
| Familiarity levels | 3 | Vision doc |
| Familiarity progression | Correct flashcard answer only | Vision doc |
| Decay | None | Vision doc |
| Reader modes supported | Paged only in MVP | Default — most common |
| OCR caching | In-memory per session, keyed by `(mangaId, chapterId, pageIndex, imageHash)`. Persist to Core Data deferred. | Default — minimize migration risk |
| Storage | Core Data, lightweight migration (matches existing `CoreDataManager`) | Existing pattern |
| Backup integration | Yes, vocab + familiarity included; flashcard state and OCR cache excluded | Default — backup matters for vocab, ephemeral state doesn't |
| Sentence grouping | LLM-prompted via Foundation Models, fragments → grouped sentences | Vision doc |
| Module location | `Shared/Learner/`, `iOS/UI/Learner/` | Vision doc fork-isolation strategy |
| Localization keys | `LEARNER_*` prefix | Default — matches `READER_*`, `LIBRARY_*` patterns |
| Per-manga setting key | `Learner.enabled.<mangaId>` | Matches `Reader.readingMode.<mangaId>` pattern |
| Test framework | Swift Testing (`import Testing`) | Existing pattern at `AidokuTests/TrackerSyncTests.swift:8-12` |
| Live Text coexistence | Disable Aidoku's existing Live Text (`Reader.liveText`) when Learner mode is on for the same page; Learner mode owns the overlay | Default — avoid double interaction layers |
