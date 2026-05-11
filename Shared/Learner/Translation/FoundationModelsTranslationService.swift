//
//  FoundationModelsTranslationService.swift
//  Aidoku
//
//  Concrete TranslationService implementation using Apple Foundation Models (iOS 26+).
//  All FoundationModels API calls are guarded by #available(iOS 26.0, *).
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Default translation service using on-device Apple Foundation Models.
/// Requires iOS 26.0+. Returns `TranslationError.unavailable` on older OS.
final class FoundationModelsTranslationService: TranslationService {

    // MARK: — Generable output types (iOS 26+)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct WordTranslationResult {
        let lemma: String
        let translation: String
        let partOfSpeech: String?
        let exampleSentence: String?
    }

    @available(iOS 26.0, *)
    @Generable
    struct SentenceTranslationResult {
        let translation: String
    }

    @available(iOS 26.0, *)
    @Generable
    struct SimplifyResult {
        let simplified: String
    }

    @available(iOS 26.0, *)
    @Generable
    struct SentenceGroupItem {
        let fragmentIndices: [Int]
        let combinedText: String
    }

    @available(iOS 26.0, *)
    @Generable
    struct SentenceGroupResult {
        let groups: [SentenceGroupItem]
    }
    #endif

    // MARK: — TranslationService

    func translateWord(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> WordTranslation {
        guard #available(iOS 26.0, *) else { throw TranslationError.unavailable }
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let prompt = """
        Translate the word "\(word)" from \(sourceLanguage) to \(targetLanguage).
        Provide the base lemma, its translation, its part of speech, and a short example sentence using the word in \(sourceLanguage).
        """
        do {
            let response = try await session.respond(to: prompt, generating: WordTranslationResult.self)
            return WordTranslation(
                lemma: response.content.lemma,
                translation: response.content.translation,
                partOfSpeech: response.content.partOfSpeech,
                exampleSentence: response.content.exampleSentence
            )
        } catch {
            print("[Learner] Foundation Models word translation failed: \(error)")
            throw TranslationError.networkError(underlying: error)
        }
        #else
        throw TranslationError.unavailable
        #endif
    }

    func translateSentence(
        _ sentence: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> SentenceTranslation {
        guard #available(iOS 26.0, *) else { throw TranslationError.unavailable }
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let prompt = "Translate this \(sourceLanguage) sentence to \(targetLanguage). Output the translation only.\n\nSentence: \(sentence)"
        do {
            let response = try await session.respond(to: prompt, generating: SentenceTranslationResult.self)
            return SentenceTranslation(original: sentence, translation: response.content.translation)
        } catch {
            print("[Learner] Foundation Models sentence translation failed: \(error)")
            throw TranslationError.networkError(underlying: error)
        }
        #else
        throw TranslationError.unavailable
        #endif
    }

    func simplifyToCEFR(
        _ sentence: String,
        level: CEFRLevel,
        language: String
    ) async throws -> String {
        guard #available(iOS 26.0, *) else { throw TranslationError.unavailable }
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let prompt = """
        Rephrase the following \(language) text at CEFR level \(level.rawValue). \
        Keep meaning intact; use simpler vocabulary and shorter sentences. \
        Output the rephrased text only, no commentary.

        Text: \(sentence)
        """
        do {
            let response = try await session.respond(to: prompt, generating: SimplifyResult.self)
            return response.content.simplified
        } catch {
            print("[Learner] Foundation Models simplification failed: \(error)")
            throw TranslationError.networkError(underlying: error)
        }
        #else
        throw TranslationError.unavailable
        #endif
    }

    func groupFragmentsIntoSentences(
        _ fragments: [TextFragment],
        language: String
    ) async throws -> [SentenceGroup] {
        guard !fragments.isEmpty else { return [] }
        guard #available(iOS 26.0, *) else { throw TranslationError.unavailable }
        #if canImport(FoundationModels)
        let fragmentList = fragments.map { "\($0.index): \"\($0.text)\"" }.joined(separator: "\n")
        let prompt = """
        Below are text fragments detected in a single manga page in \(language). \
        Some fragments form a complete sentence; others are isolated words or sound effects. \
        Group fragments by sentence in reading order. Each group's combinedText is the fragments \
        joined with spaces, lightly cleaned (no other edits). Return ONE group per sentence.

        Fragments:
        \(fragmentList)
        """
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt, generating: SentenceGroupResult.self)
            return response.content.groups.map {
                SentenceGroup(fragmentIndices: $0.fragmentIndices, combinedText: $0.combinedText)
            }
        } catch {
            print("[Learner] Foundation Models fragment grouping failed: \(error)")
            throw TranslationError.networkError(underlying: error)
        }
        #else
        throw TranslationError.unavailable
        #endif
    }
}
