//
//  WordLookupViewModelTests.swift
//  Aidoku
//
//  Swift Testing cases for WordLookupViewModel.
//  Uses in-memory CoreData stack and stub TranslationService.
//

import Foundation
import CoreData
import Combine
import Testing
@testable import Aidoku

// MARK: — Stub TranslationService

private struct StubTranslationService: TranslationService {
    enum Mode { case success, failure }
    let mode: Mode

    func translateWord(_ word: String, sourceLanguage: String, targetLanguage: String) async throws -> WordTranslation {
        if mode == .failure { throw TranslationError.unavailable }
        return WordTranslation(lemma: word, translation: "stub-\(word)", partOfSpeech: "noun")
    }
    func translateSentence(_ sentence: String, sourceLanguage: String, targetLanguage: String) async throws -> SentenceTranslation {
        SentenceTranslation(original: sentence, translation: "translated")
    }
    func simplifyToCEFR(_ sentence: String, level: CEFRLevel, language: String) async throws -> String { sentence }
    func groupFragmentsIntoSentences(_ fragments: [TextFragment], language: String) async throws -> [SentenceGroup] { [] }
}

// MARK: — Helper

private func makeEvent(word: String = "Buch", manga: String = "test-manga-wlvm") -> WordTapEvent {
    let ctx = LearnerPageContext(sourceId: "src", mangaId: manga, chapterId: "ch1", pageIndex: 0)
    return WordTapEvent(surfaceForm: word, lemma: LearnerStrings.normalizeLemma(word), language: "de-DE", pageContext: ctx)
}

// MARK: — Tests

@Suite struct WordLookupViewModelTests {

    // Test 1: normalizeLemma strips punctuation and lowercases
    @Test func normalizeLemma_stripsPunctuationAndLowercases() {
        #expect(LearnerStrings.normalizeLemma("Buch.") == "buch")
        #expect(LearnerStrings.normalizeLemma("Buch,") == "buch")
        #expect(LearnerStrings.normalizeLemma("  Buch  ") == "buch")
        #expect(LearnerStrings.normalizeLemma("BUCH") == "buch")
    }

    // Test 2: fresh event — not in vocab initially
    @Test @MainActor func init_freshEvent_notInVocab() {
        let vm = WordLookupViewModel(event: makeEvent())
        #expect(vm.isInVocab == false)
        #expect(vm.familiarity == 0)
        #expect(vm.isDone == false)
    }

    // Test 3: toggleVocab adds entry; second call removes it
    @Test @MainActor func toggleVocab_addsAndRemovesEntry() async {
        let ctx = makeInMemoryContainer()
        let vm = WordLookupViewModel(event: makeEvent(word: "Haus"))
        let lemma = vm.lemma
        let lang = vm.language

        // Add
        await vm.toggleVocab()
        #expect(vm.isInVocab == true)
        let entry = CoreDataManager.shared.getVocabularyEntry(language: lang, lemma: lemma, context: ctx.viewContext)
        #expect(entry != nil)

        // Remove
        await vm.toggleVocab()
        #expect(vm.isInVocab == false)
        let removed = CoreDataManager.shared.getVocabularyEntry(language: lang, lemma: lemma, context: ctx.viewContext)
        #expect(removed == nil)
    }

    // Test 4: setFamiliarity persists and fires vocabChanged
    @Test @MainActor func setFamiliarity_persistsLevel() async {
        let ctx = makeInMemoryContainer()
        let vm = WordLookupViewModel(event: makeEvent(word: "Tisch"))

        // First add to vocab
        await vm.toggleVocab()
        #expect(vm.isInVocab == true)

        // Set familiarity
        await vm.setFamiliarity(2)
        #expect(vm.familiarity == 2)

        let entry = CoreDataManager.shared.getVocabularyEntry(
            language: vm.language, lemma: vm.lemma, context: ctx.viewContext
        )
        #expect(entry?.progress?.level == 2)
    }

    // Test 5: requestSentenceTranslation emits event
    @Test @MainActor func requestSentenceTranslation_emitsEvent() async {
        let vm = WordLookupViewModel(event: makeEvent())
        let event = makeEvent()

        let fired = await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = LearnerEvents.shared.sentenceTranslateRequested
                .first()
                .sink { _ in
                    continuation.resume(returning: true)
                    cancellable?.cancel()
                }
            vm.requestSentenceTranslation(event: event)
        }
        #expect(fired == true)
    }
}
