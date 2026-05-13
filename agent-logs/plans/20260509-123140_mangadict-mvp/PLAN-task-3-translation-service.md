---
task: 3
task_name: "translation-service"
status: planned
created: 2026-05-09
steps_total: 7
steps_completed: 0
estimated_files: 9
parallelizable_with: [2, 4]
depends_on: [1]
---

# Task 3 — Translation Service (Apple Foundation Models + DeepL Fallback)

## Goal

Build a single `TranslationService` that fronts Apple Foundation Models for word translation, sentence translation, sentence simplification, and fragment-to-sentence grouping — with DeepL as an optional BYO API key override for word and sentence translation only.

## Acceptance Criteria

- [ ] `TranslationService` protocol exists at `Shared/Learner/Translation/TranslationService.swift` with these async methods:
  - `translateWord(_ word: String, sourceLanguage: String, targetLanguage: String) async throws -> WordTranslation`
  - `translateSentence(_ sentence: String, sourceLanguage: String, targetLanguage: String) async throws -> SentenceTranslation`
  - `simplifyToCEFR(_ sentence: String, level: CEFRLevel, language: String) async throws -> String`
  - `groupFragmentsIntoSentences(_ fragments: [TextFragment], language: String) async throws -> [SentenceGroup]`
- [ ] `FoundationModelsTranslationService` (default impl) calls Apple Foundation Models APIs on iOS 26+. Falls back to a stub that throws `.unavailable` on older OS.
- [ ] `DeepLTranslationService` calls DeepL's REST API and is selected for word + sentence translation only when a non-empty `Learner.deepLAPIKey` is set in `UserDefaults`. Simplification and sentence-grouping always use Foundation Models (DeepL doesn't do those).
- [ ] A `TranslationServiceFactory.shared` returns the right composite service based on current settings. Settings change live (re-check on next call, not at app launch).
- [ ] In-memory LRU cache (capacity 500 entries) on top of every method, keyed by `(method, sourceLang, targetLang, input)`. Cache is per-process; clears on app relaunch.
- [ ] Unit tests cover: cache hit returns without calling underlying service; DeepL is preferred when key is set; fallback to Foundation Models when DeepL request fails; sentence grouping returns sentences whose fragments concatenate (in order) to the input fragments' joined text up to whitespace differences.
- [ ] No network requests fire when DeepL key is empty (verified by injecting a `URLSession` mock that records requests).
- [ ] All user-facing errors are mapped to `LEARNER_TRANSLATION_*` localized strings; raw network errors never reach UI.

## What This Is Not

- No translation provider beyond Foundation Models + DeepL. Google Translate / Azure / Yandex deferred.
- No background prefetch — translations happen lazily on tap / button press. Caching is the only optimization.
- No persistent translation cache — every cache miss after relaunch hits the model. Acceptable since on-device Foundation Models are free and fast.
- No streaming output — translations return as a single completion.
- No tone / register controls beyond CEFR level for simplification.

## Approach

### Layering

```
TranslationServiceFactory.shared
  └─ CachingTranslationService (wraps any service)
       └─ CompositeTranslationService (routes methods)
            ├─ DeepLTranslationService     (word + sentence translation, when API key is set)
            └─ FoundationModelsTranslationService  (everything else, and fallback)
```

`CachingTranslationService` wraps every method and consults an `NSCache`-backed LRU before delegating. `CompositeTranslationService` decides per-method which underlying service to call.

### Foundation Models usage

Apple Foundation Models on iOS 26+ are exposed via the `FoundationModels` framework. The pattern (per Apple's docs): create a `LanguageModelSession`, call `respond(to: prompt, generating:)` for structured output. We define `@Generable` Swift structs for each output shape:

```swift
@Generable
struct WordTranslationResult {
    let lemma: String
    let translation: String
    let partOfSpeech: String?
    let exampleSentence: String?
}

@Generable
struct SentenceGroupResult {
    let groups: [SentenceGroupItem]
}
@Generable
struct SentenceGroupItem {
    let fragmentIndices: [Int]
    let combinedText: String
}
```

If the `FoundationModels` framework is unavailable at compile time (older Xcode / SDK), the entire `FoundationModelsTranslationService` file is wrapped in `#if canImport(FoundationModels)` / `#available(iOS 26.0, *)` checks; the fallback path returns a `TranslationError.unavailable` immediately. (We require iOS 26+ at deployment target per `Aidoku.xcodeproj/project.pbxproj` — but compile-time guards keep the code resilient.)

### DeepL usage

`DeepLTranslationService` posts to `https://api-free.deepl.com/v2/translate` (free tier) by default. The endpoint base is configurable via `Learner.deepLAPIBase` UserDefault (so users with paid plans can switch to `api.deepl.com`). Authorization header is `Authorization: DeepL-Auth-Key <key>`. The service is a thin wrapper — no retry logic beyond Aidoku's existing networking conventions (use `URLSession.shared`).

For per-word translation, DeepL doesn't return part-of-speech; we leave `partOfSpeech` and `exampleSentence` nil when DeepL is in use.

### Sentence grouping prompt

Foundation Models receives:

```
Below are text fragments detected in a single manga page in <LANG>. Some fragments form a complete sentence; others are isolated words or sound effects. Group fragments by sentence in reading order. Each group's combinedText is the fragments joined with spaces, lightly cleaned (no other edits). Return ONE group per sentence.

Fragments:
0: "<text>"
1: "<text>"
...
```

Result is the `SentenceGroupResult` `@Generable` struct.

### Simplification prompt

```
Rephrase the following <LANG> text at CEFR level <LEVEL> (e.g. A2). Keep meaning intact; use simpler vocabulary and shorter sentences. Output the rephrased text only, no commentary.

Text: <text>
```

### Settings keys

| UserDefaults key | Type | Default | Purpose |
|---|---|---|---|
| `Learner.deepLAPIKey` | String | `""` | Empty disables DeepL |
| `Learner.deepLAPIBase` | String | `"https://api-free.deepl.com"` | Free vs paid |
| `Learner.simplificationLevel` | String | `"A2"` | CEFR level for simplify |
| `Learner.targetLanguage` | String | `"en"` | UI language for translations |

## Decision Register

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Default translator | Apple Foundation Models | Vision doc; on-device |
| 2 | Optional override | DeepL only | Vision doc; best German quality among BYO options |
| 3 | DeepL methods | Word + sentence translation only | DeepL doesn't simplify or group fragments |
| 4 | Sentence grouping | Foundation Models with `@Generable` structured output | Vision doc; avoids algorithmic region-segmentation |
| 5 | Cache | In-memory LRU 500 entries via `NSCache` | Default — cheap, no migration, persists across views within session |
| 6 | Cache key | `(method, sourceLang, targetLang, input)` | Default — covers all cache invalidation cases |
| 7 | Threading | All methods `async throws`, internal work via Foundation Models' own queues | Matches Swift concurrency conventions |
| 8 | Settings storage | UserDefaults keys under `Learner.*` | Matches `Reader.upscaleImages` precedent |
| 9 | Error surfacing | `TranslationError` enum mapped to `LEARNER_TRANSLATION_*` localized strings | Default — consistent UX |
| 10 | DeepL endpoint | Free tier default, configurable | Default — most users will start with free |
| 11 | Compile-time guard | `#available(iOS 26.0, *)` around Foundation Models calls; deployment target already 26.0 | Defensive — protects future Xcode upgrades or SPI changes |
| 12 | Test framework | Swift Testing | Matches Aidoku convention |

## Files Touched

| Action | File Path | What Changes |
|--------|-----------|--------------|
| CREATE | `Shared/Learner/Translation/TranslationService.swift` | Protocol + supporting types (`WordTranslation`, `SentenceTranslation`, `SentenceGroup`, `TextFragment`, `CEFRLevel`, `TranslationError`) |
| CREATE | `Shared/Learner/Translation/FoundationModelsTranslationService.swift` | Concrete impl using `FoundationModels` framework |
| CREATE | `Shared/Learner/Translation/DeepLTranslationService.swift` | Concrete impl using `URLSession` to DeepL REST |
| CREATE | `Shared/Learner/Translation/CompositeTranslationService.swift` | Routes calls to DeepL or Foundation Models based on settings |
| CREATE | `Shared/Learner/Translation/CachingTranslationService.swift` | LRU cache wrapper |
| CREATE | `Shared/Learner/Translation/TranslationServiceFactory.swift` | Singleton factory; reads UserDefaults at every call to allow live settings updates |
| MODIFY | `Shared/Localization/en.lproj/Localizable.strings` | Add `LEARNER_TRANSLATION_UNAVAILABLE`, `LEARNER_TRANSLATION_NETWORK_ERROR`, `LEARNER_TRANSLATION_INVALID_KEY` |
| CREATE | `AidokuTests/TranslationServiceTests.swift` | Cache, routing, fallback, grouping invariant tests |
| MODIFY | `Aidoku.xcodeproj/project.pbxproj` | Add files to targets |

## Implementation Steps

- [ ] **Step 1: Define protocol + types** (`TranslationService.swift`)
  - **What:** `protocol TranslationService` with the four async methods. Value types for inputs/outputs (`WordTranslation`, `SentenceTranslation`, `SentenceGroup`, `TextFragment`, `CEFRLevel` enum, `TranslationError` enum). All `Sendable`.
  - **Verify by:** Compile passes.

- [ ] **Step 2: Implement `FoundationModelsTranslationService`**
  - **What:** Concrete class. Each method creates a `LanguageModelSession`, builds the prompt, calls `session.respond(to: prompt, generating: ResultType.self)`, maps to public type. Wrap in `#available(iOS 26.0, *)`. Throw `.unavailable` on older OS.
  - **Files:** `FoundationModelsTranslationService.swift`
  - **Verify by:** Manual test in step 7's harness on a simulator: `translateWord("Buch", "de", "en")` returns "book".

- [ ] **Step 3: Implement `DeepLTranslationService`**
  - **What:** `translateWord` and `translateSentence` POST to DeepL. `simplifyToCEFR` and `groupFragmentsIntoSentences` throw `.notSupportedByProvider`. Use `URLSession.shared`. Parse standard DeepL JSON response (`translations[0].text`).
  - **Files:** `DeepLTranslationService.swift`
  - **Depends on:** Step 1
  - **Verify by:** Test using a `URLProtocol` mock; assert correct request headers and parsed output.

- [ ] **Step 4: Implement `CompositeTranslationService`**
  - **What:** Reads `Learner.deepLAPIKey` per call. If non-empty: uses DeepL for word + sentence translation, catches `.notSupportedByProvider` and falls through to Foundation Models for simplification + grouping. On DeepL network error: falls back to Foundation Models for that call (logs but doesn't surface).
  - **Files:** `CompositeTranslationService.swift`
  - **Depends on:** Steps 2, 3
  - **Verify by:** Unit test in step 7.

- [ ] **Step 5: Implement `CachingTranslationService`**
  - **What:** Wraps any `TranslationService`. Uses `NSCache<NSString, AnyObject>` with `countLimit = 500`. Key = `"\(method)|\(srcLang)|\(tgtLang)|\(inputHash)"`. Cache values are wrapped in `_ObjC`-compatible class boxes since `NSCache` requires reference types.
  - **Files:** `CachingTranslationService.swift`
  - **Depends on:** Step 1
  - **Verify by:** Unit test asserts a second call with identical args doesn't hit the underlying service (use a recording mock).

- [ ] **Step 6: Implement `TranslationServiceFactory.shared.current()`**
  - **What:** Returns `CachingTranslationService(wrapping: CompositeTranslationService(...))`. Re-reads UserDefaults each call (cheap; UserDefaults is in-memory after first read).
  - **Files:** `TranslationServiceFactory.swift`
  - **Depends on:** Steps 4, 5
  - **Verify by:** Unit test mutates `Learner.deepLAPIKey` and confirms next call routes differently.

- [ ] **Step 7: Tests**
  - **What:** `AidokuTests/TranslationServiceTests.swift` covers the cases in Acceptance Criteria. Mock `FoundationModelsTranslationService` and `DeepLTranslationService` with stubs to make tests deterministic. One integration smoke test (gated by `ProcessInfo.processInfo.environment["DEEPL_TEST_KEY"]`) actually hits DeepL — skipped in CI.
  - **Files:** `TranslationServiceTests.swift`
  - **Depends on:** Steps 4–6
  - **Verify by:** `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/TranslationServiceTests` passes.

## Testing Strategy

- File: `AidokuTests/TranslationServiceTests.swift`.
- Mock services that record arguments; in-memory cache under test.
- One real-network test gated by env var (off by default).
- Run command: `xcodebuild -scheme Aidoku test -only-testing:AidokuTests/TranslationServiceTests -destination 'platform=iOS Simulator,name=iPhone 16'`.

## Risks

- **Most complex part:** Foundation Models structured-output API surface may shift between iOS 26 betas. The `@Generable` macro and `LanguageModelSession.respond(to:generating:)` shape used here are based on Apple's WWDC '25 doc. If signatures change, every call site needs adjustment. Mitigation: isolate all `FoundationModels` calls in `FoundationModelsTranslationService.swift`; the protocol abstracts them away from the rest of the app.
- **Most-likely-wrong assumption:** That on-device Foundation Models can handle nuanced literary German at usable quality. The vision doc itself flags this. Mitigation: DeepL fallback is wired in MVP, not deferred.
- **Edge case:** A DeepL API key that's valid format but expired / rate-limited. The current plan falls back silently to Foundation Models on network error. This is correct UX for personal use but logs should surface the underlying error in `Logger` for the maintainer to debug.
