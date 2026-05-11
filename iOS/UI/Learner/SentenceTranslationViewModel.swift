//
//  SentenceTranslationViewModel.swift
//  Aidoku (iOS)
//
//  ObservableObject view model for SentenceTranslationSheet.
//  Groups OCR fragments into sentences, translates them in parallel,
//  and provides on-demand CEFR simplification.
//

import Foundation
import Combine

// MARK: — SentenceVM

/// View-level representation of one translated sentence.
struct SentenceVM: Identifiable {
    let id: UUID = UUID()
    /// Source-language sentence text.
    let source: String
    /// Populated as each parallel translation arrives.
    var translation: String?
    /// Populated lazily when the user expands the simplification row.
    var simplified: String?
    /// Whether the simplification disclosure row is expanded.
    var simplifyExpanded: Bool = false
    /// Set if simplification failed.
    var simplifyError: String?
}

// MARK: — SentenceTranslationViewModel

@MainActor
final class SentenceTranslationViewModel: ObservableObject {

    // MARK: — Inputs

    let context: LearnerPageContext
    let ocrResult: OCRResult
    /// If non-nil, scroll to (or highlight) the sentence containing this lemma.
    let focusLemma: String?

    // MARK: — State

    @Published var sentences: [SentenceVM] = []
    @Published var isLoading: Bool = true
    @Published var loadError: TranslationError?

    // MARK: — Init

    init(context: LearnerPageContext, ocrResult: OCRResult, focusLemma: String? = nil) {
        self.context = context
        self.ocrResult = ocrResult
        self.focusLemma = focusLemma
    }

    // MARK: — Load

    /// Groups OCR lines into sentences, then translates each in parallel.
    func load() async {
        isLoading = true
        loadError = nil
        sentences = []

        let fragments = ocrResult.lines.enumerated().map { idx, line in
            TextFragment(text: line.text, index: idx)
        }

        guard !fragments.isEmpty else {
            isLoading = false
            return
        }

        let service = TranslationServiceFactory.shared.service
        let sourceLanguage = context.language
        let targetLanguage = UserDefaults.standard.string(forKey: "Learner.targetLanguage") ?? "en"

        // Step 1: group fragments into sentences
        let groups: [SentenceGroup]
        do {
            groups = try await service.groupFragmentsIntoSentences(fragments, language: sourceLanguage)
        } catch let err as TranslationError {
            loadError = err
            isLoading = false
            return
        } catch {
            loadError = .networkError(underlying: error)
            isLoading = false
            return
        }

        // Validate that every input fragment index appears exactly once across groups.
        // If the LLM dropped or duplicated indices, fall back to one-fragment-per-sentence.
        let inputIndices = Set(fragments.map(\.index))
        let returnedFlat = groups.flatMap(\.fragmentIndices)
        let returnedSet = Set(returnedFlat)
        let groupingIsValid = !groups.isEmpty
            && returnedSet == inputIndices
            && returnedFlat.count == inputIndices.count
        let resolvedGroups: [SentenceGroup]
        if groupingIsValid {
            resolvedGroups = groups
        } else {
            if !groups.isEmpty {
                print("[Learner] sentence grouping returned invalid fragment indices; falling back to one-per-line")
            }
            resolvedGroups = fragments.map { frag in
                SentenceGroup(fragmentIndices: [frag.index], combinedText: frag.text)
            }
        }

        // Seed sentences array with source text (no translation yet)
        sentences = resolvedGroups.map { SentenceVM(source: $0.combinedText) }
        isLoading = false

        // Step 2: translate each sentence concurrently
        await withTaskGroup(of: (Int, String?).self) { group in
            for (idx, sentenceGroup) in resolvedGroups.enumerated() {
                group.addTask {
                    let result = try? await service.translateSentence(
                        sentenceGroup.combinedText,
                        sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage
                    )
                    return (idx, result?.translation)
                }
            }
            for await (idx, translation) in group {
                if idx < sentences.count {
                    sentences[idx].translation = translation
                }
            }
        }
    }

    // MARK: — Retry

    func retry() async {
        await load()
    }

    // MARK: — Simplify (lazy, on row expand)

    func simplify(id: UUID) async {
        guard let idx = sentences.firstIndex(where: { $0.id == id }) else { return }
        guard sentences[idx].simplified == nil else { return }

        let service = TranslationServiceFactory.shared.service
        let sourceLanguage = context.language
        let rawLevel = UserDefaults.standard.string(forKey: "Learner.simplificationLevel") ?? "A2"
        let level = CEFRLevel(rawValue: rawLevel) ?? .a2
        let text = sentences[idx].source

        do {
            let simplified = try await service.simplifyToCEFR(text, level: level, language: sourceLanguage)
            sentences[idx].simplified = simplified
            sentences[idx].simplifyError = nil
        } catch {
            sentences[idx].simplifyError = "LEARNER_SENTENCE_LOAD_ERROR".localized
        }
    }
}

// MARK: — LearnerPageContext language helper

extension LearnerPageContext {
    /// Derives the source language tag from the OCR language stored in UserDefaults.
    /// Currently global; per-manga language is tracked as I11 in the review backlog.
    var language: String {
        if let lang = UserDefaults.standard.string(forKey: "Learner.ocrLanguages"), !lang.isEmpty {
            return lang
        }
        return "de-DE"
    }
}

// MARK: — Localization

private extension String {
    var localized: String { NSLocalizedString(self, comment: "") }
}
