//
//  WordLookupViewModel.swift
//  Aidoku (iOS)
//
//  ObservableObject view model backing WordLookupSheet.
//  Handles translation loading, vocab membership, familiarity, and done-locking.
//

import Foundation
import Combine
#if canImport(Translation)
import Translation
#endif

@MainActor
final class WordLookupViewModel: ObservableObject {

    // MARK: — Inputs (immutable after init)

    let surfaceForm: String
    let lemma: String
    let language: String
    let mangaId: String
    let sourceId: String

    // MARK: — State

    @Published var translation: WordTranslation?
    @Published var isInVocab: Bool = false
    @Published var familiarity: Int16 = 0
    @Published var isDone: Bool = false
    @Published var loadError: TranslationError?
    @Published var isLoading: Bool = false

    // MARK: — Init

    init(event: WordTapEvent) {
        self.surfaceForm = event.surfaceForm
        self.lemma = LearnerStrings.normalizeLemma(event.surfaceForm)
        self.language = event.language
        self.mangaId = event.pageContext.mangaId
        self.sourceId = event.pageContext.sourceId
        loadVocabState()
    }

    /// Init for vocab-only mode (from Vocabulary list — no page context needed).
    init(entry: VocabularyEntryObject) {
        self.surfaceForm = entry.surfaceForm
        self.lemma = entry.lemma
        self.language = entry.language
        self.mangaId = entry.sourceMangaId ?? ""
        self.sourceId = entry.sourceMangaSourceId ?? ""
        self.isInVocab = true
        self.familiarity = entry.progress?.level ?? 0
        self.isDone = entry.progress?.done ?? false
        // Use cached translation if available
        if let t = entry.translation {
            self.translation = WordTranslation(lemma: entry.lemma, translation: t)
        }
    }

    // MARK: — Vocab state

    private func loadVocabState() {
        if let entry = CoreDataManager.shared.getVocabularyEntry(language: language, lemma: lemma) {
            isInVocab = true
            familiarity = entry.progress?.level ?? 0
            isDone = entry.progress?.done ?? false
            if let t = entry.translation {
                translation = WordTranslation(lemma: lemma, translation: t)
            }
        }
    }

    // MARK: — Translation

    func loadTranslation() async {
        guard translation == nil else { return }
        isLoading = true
        loadError = nil
        do {
            let targetLang = UserDefaults.standard.string(forKey: "Learner.targetLanguage") ?? "en"
            let result = try await TranslationServiceFactory.shared.service
                .translateWord(lemma, sourceLanguage: language, targetLanguage: targetLang)
            translation = result
            // Cache in CoreData if word is in vocab
            if isInVocab {
                _ = CoreDataManager.shared.upsertVocabularyEntry(
                    language: language,
                    lemma: lemma,
                    surfaceForm: surfaceForm,
                    translation: result.translation,
                    sourceMangaId: mangaId.isEmpty ? nil : mangaId,
                    sourceMangaSourceId: sourceId.isEmpty ? nil : sourceId
                )
            }
        } catch let err as TranslationError {
            loadError = err
        } catch {
            loadError = .networkError(underlying: error)
        }
        isLoading = false
    }

    // MARK: — Vocab membership

    func toggleVocab() async {
        if isInVocab {
            // Remove
            if let entry = CoreDataManager.shared.getVocabularyEntry(language: language, lemma: lemma) {
                CoreDataManager.shared.removeVocabularyEntry(entry)
                isInVocab = false
                familiarity = 0
                isDone = false
            }
        } else {
            // Add
            _ = CoreDataManager.shared.upsertVocabularyEntry(
                language: language,
                lemma: lemma,
                surfaceForm: surfaceForm,
                translation: translation?.translation,
                sourceMangaId: mangaId.isEmpty ? nil : mangaId,
                sourceMangaSourceId: sourceId.isEmpty ? nil : sourceId
            )
            isInVocab = true
        }
        LearnerEvents.shared.vocabChanged.send()
    }

    // MARK: — Familiarity

    func setFamiliarity(_ level: Int16) async {
        guard isInVocab,
              let entry = CoreDataManager.shared.getVocabularyEntry(language: language, lemma: lemma) else { return }
        CoreDataManager.shared.setFamiliarity(entry, level: level)
        familiarity = level
        LearnerEvents.shared.vocabChanged.send()
    }

    // MARK: — Done

    func markDone() async {
        guard isInVocab,
              let entry = CoreDataManager.shared.getVocabularyEntry(language: language, lemma: lemma) else { return }
        CoreDataManager.shared.setDone(entry)
        isDone = true
        familiarity = 3
        LearnerEvents.shared.vocabChanged.send()
    }

    // MARK: — Sentence translation hand-off

    func requestSentenceTranslation(event: WordTapEvent) {
        LearnerEvents.shared.sentenceTranslateRequested.send(event)
    }

    // MARK: — Apple Translation framework

    #if canImport(Translation)
    @available(iOS 18.0, *)
    func loadTranslation(using session: TranslationSession) async {
        guard translation == nil else { return }
        isLoading = true
        loadError = nil
        do {
            let response = try await session.translate(lemma)
            let result = WordTranslation(lemma: lemma, translation: response.targetText)
            translation = result
            if isInVocab {
                _ = CoreDataManager.shared.upsertVocabularyEntry(
                    language: language,
                    lemma: lemma,
                    surfaceForm: surfaceForm,
                    translation: result.translation,
                    sourceMangaId: mangaId.isEmpty ? nil : mangaId,
                    sourceMangaSourceId: sourceId.isEmpty ? nil : sourceId
                )
            }
        } catch {
            loadError = .networkError(underlying: error)
        }
        isLoading = false
    }
    #endif
}
