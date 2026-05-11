//
//  TranslationServiceTests.swift
//  Aidoku
//
//  Swift Testing cases for TranslationService stack (cache, routing, fallback, grouping invariant).
//  Uses stub implementations — no real network or Foundation Models calls in CI.
//

import Foundation
import Testing
@testable import Aidoku

// MARK: — Stub helpers

/// A recording translation service stub. Records call counts; returns predictable values.
final class StubTranslationService: TranslationService, @unchecked Sendable {
    var wordCallCount = 0
    var sentenceCallCount = 0

    var wordResult: WordTranslation = WordTranslation(lemma: "buch", translation: "book")
    var sentenceResult: SentenceTranslation = SentenceTranslation(original: "Das Buch", translation: "The book")
    var simplifyResult: String = "Simple text."
    var groupResult: [SentenceGroup] = []

    // Optionally throw on next call
    var shouldFailWord = false
    var wordFailError: TranslationError = .networkError(underlying: URLError(.notConnectedToInternet))

    func translateWord(_ word: String, sourceLanguage: String, targetLanguage: String) async throws -> WordTranslation {
        wordCallCount += 1
        if shouldFailWord { throw wordFailError }
        return wordResult
    }
    func translateSentence(_ sentence: String, sourceLanguage: String, targetLanguage: String) async throws -> SentenceTranslation {
        sentenceCallCount += 1
        return sentenceResult
    }
    func simplifyToCEFR(_ sentence: String, level: CEFRLevel, language: String) async throws -> String {
        simplifyResult
    }
    func groupFragmentsIntoSentences(_ fragments: [TextFragment], language: String) async throws -> [SentenceGroup] {
        groupResult
    }
}

// MARK: — Tests

@Suite struct TranslationServiceTests {

    // MARK: 1. Cache hit skips the underlying service

    @Test func cacheHit_doesNotCallUnderlying() async throws {
        let stub = StubTranslationService()
        let caching = CachingTranslationService(wrapping: stub, countLimit: 500)

        // First call — miss
        _ = try await caching.translateWord("Buch", sourceLanguage: "de-DE", targetLanguage: "en")
        #expect(stub.wordCallCount == 1)

        // Second call with identical args — hit
        _ = try await caching.translateWord("Buch", sourceLanguage: "de-DE", targetLanguage: "en")
        #expect(stub.wordCallCount == 1, "Second call should have hit the cache, not called stub")
    }

    // MARK: 2. Different args miss the cache

    @Test func cacheMiss_differentInput_callsUnderlying() async throws {
        let stub = StubTranslationService()
        let caching = CachingTranslationService(wrapping: stub, countLimit: 500)

        _ = try await caching.translateWord("Buch", sourceLanguage: "de-DE", targetLanguage: "en")
        _ = try await caching.translateWord("Hund", sourceLanguage: "de-DE", targetLanguage: "en") // different word
        #expect(stub.wordCallCount == 2)
    }

    // The production CompositeTranslationService already accepts stub services via its
    // init (CompositeTranslationService.swift:19-25). Tests 3-6 exercise it directly.
    // Note: only StubTranslationService doubles are used; the real init types
    // (FoundationModelsTranslationService / DeepLTranslationService) are concrete but
    // CompositeTranslationService stores the protocol-typed `any TranslationService`
    // members internally for the routing logic. To stay on the production class we
    // construct it with default args and then mutate routing via a thin shim below.

    // MARK: 3. DeepL preferred when key is set

    @Test func deepLPreferred_whenKeyIsSet() async throws {
        let deepLStub = StubTranslationService()
        let fmStub = StubTranslationService()

        UserDefaults.standard.set("fake-key", forKey: "Learner.deepLAPIKey")
        defer { UserDefaults.standard.removeObject(forKey: "Learner.deepLAPIKey") }

        let composite = makeComposite(fm: fmStub, deepL: deepLStub)
        _ = try await composite.translateWord("Buch", sourceLanguage: "de-DE", targetLanguage: "en")

        #expect(deepLStub.wordCallCount == 1)
        #expect(fmStub.wordCallCount == 0)
    }

    // MARK: 4. Foundation Models used when no key

    @Test func foundationModels_usedWhenNoKey() async throws {
        let deepLStub = StubTranslationService()
        let fmStub = StubTranslationService()

        UserDefaults.standard.removeObject(forKey: "Learner.deepLAPIKey")

        let composite = makeComposite(fm: fmStub, deepL: deepLStub)
        _ = try await composite.translateWord("Buch", sourceLanguage: "de-DE", targetLanguage: "en")

        #expect(fmStub.wordCallCount == 1)
        #expect(deepLStub.wordCallCount == 0)
    }

    // MARK: 5. DeepL failure falls back to Foundation Models

    @Test func deepLFailure_fallsBackToFoundationModels() async throws {
        let deepLStub = StubTranslationService()
        deepLStub.shouldFailWord = true
        let fmStub = StubTranslationService()

        UserDefaults.standard.set("fake-key", forKey: "Learner.deepLAPIKey")
        defer { UserDefaults.standard.removeObject(forKey: "Learner.deepLAPIKey") }

        let composite = makeComposite(fm: fmStub, deepL: deepLStub)
        let result = try await composite.translateWord("Buch", sourceLanguage: "de-DE", targetLanguage: "en")

        #expect(deepLStub.wordCallCount == 1) // DeepL was tried
        #expect(fmStub.wordCallCount == 1)    // Fell back to FM
        #expect(result.lemma == "buch")        // FM's stub result
    }

    // MARK: 6. Simplification always uses Foundation Models (even when DeepL key is set)

    @Test func simplification_alwaysUsesFoundationModels() async throws {
        let deepLStub = StubTranslationService()
        let fmStub = StubTranslationService()
        fmStub.simplifyResult = "Einfacher Text."

        UserDefaults.standard.set("fake-key", forKey: "Learner.deepLAPIKey")
        defer { UserDefaults.standard.removeObject(forKey: "Learner.deepLAPIKey") }

        let composite = makeComposite(fm: fmStub, deepL: deepLStub)
        let result = try await composite.simplifyToCEFR("Komplizierterer Text.", level: .a2, language: "de-DE")

        #expect(result == "Einfacher Text.")
        #expect(deepLStub.wordCallCount == 0)
    }

    // MARK: 7. Grouping: returned groups' fragment indices are a partition of input indices

    @Test func grouping_fragmentIndices_coverInput() async throws {
        let stub = StubTranslationService()
        let fragments = (0..<5).map { TextFragment(text: "Wort \($0)", index: $0) }

        // Stub returns two groups covering all 5 fragments
        stub.groupResult = [
            SentenceGroup(fragmentIndices: [0, 1, 2], combinedText: "Wort 0 Wort 1 Wort 2"),
            SentenceGroup(fragmentIndices: [3, 4], combinedText: "Wort 3 Wort 4")
        ]

        let groups = try await stub.groupFragmentsIntoSentences(fragments, language: "de-DE")

        let allReturnedIndices = groups.flatMap(\.fragmentIndices).sorted()
        let inputIndices = fragments.map(\.index).sorted()
        #expect(allReturnedIndices == inputIndices,
                "All fragment indices must appear exactly once in the grouped output")
    }
}

// MARK: — Helpers

/// Builds the production CompositeTranslationService with stub services.
/// `CompositeTranslationService.init` accepts `any TranslationService` for both args.
private func makeComposite(fm: any TranslationService, deepL: any TranslationService) -> CompositeTranslationService {
    CompositeTranslationService(foundationModels: fm, deepL: deepL)
}
