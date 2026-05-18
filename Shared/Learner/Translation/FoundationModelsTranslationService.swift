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

    /// Foundation Models handles raw BCP-47 tags ("tr-TR", "en") inconsistently —
    /// echoing the source for less common pairings. Pass the language *name* in
    /// English so the prompt is unambiguous.
    static func languageName(for tag: String) -> String {
        let primary = String(tag.split(separator: "-").first ?? Substring(tag))
        let en = Locale(identifier: "en_US")
        if let name = en.localizedString(forLanguageCode: primary), !name.isEmpty {
            return name
        }
        return tag
    }

    /// Returns the primary subtag ("tr-TR" → "tr").
    private static func primarySubtag(_ tag: String) -> String {
        String(tag.split(separator: "-").first ?? Substring(tag)).lowercased()
    }

    /// Post-processes a translation output to remove Turkish-specific dotted/dotless I
    /// characters when the target language is not Turkish. The on-device model
    /// occasionally applies Turkish-locale capitalization to English output
    /// ("In place" → "İn place"). Mapping "İ" → "I" and "ı" → "i" is safe for every
    /// other supported target language (English, German, French, Spanish, Japanese).
    static func sanitizeTranslation(_ text: String, targetLanguage: String) -> String {
        guard primarySubtag(targetLanguage) != "tr" else { return text }
        return text
            .replacingOccurrences(of: "\u{0130}", with: "I")  // İ → I
            .replacingOccurrences(of: "\u{0131}", with: "i")  // ı → i
    }

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
        let sourceName = Self.languageName(for: sourceLanguage)
        let targetName = Self.languageName(for: targetLanguage)
        let prompt = """
        Translate the word "\(word)" from \(sourceName) to \(targetName).
        Provide the base lemma, its translation in \(targetName), its part of speech, and a short example sentence using the word in \(sourceName).
        The translation field MUST be written in \(targetName), not in \(sourceName).
        """
        do {
            let response = try await session.respond(to: prompt, generating: WordTranslationResult.self)
            return WordTranslation(
                lemma: response.content.lemma,
                translation: Self.sanitizeTranslation(response.content.translation, targetLanguage: targetLanguage),
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
        let sourceName = Self.languageName(for: sourceLanguage)
        let targetName = Self.languageName(for: targetLanguage)
        let prompt = "Translate this \(sourceName) sentence to \(targetName). The output MUST be written in \(targetName), not \(sourceName). Output the translation only.\n\nSentence: \(sentence)"
        do {
            let response = try await session.respond(to: prompt, generating: SentenceTranslationResult.self)
            return SentenceTranslation(
                original: sentence,
                translation: Self.sanitizeTranslation(response.content.translation, targetLanguage: targetLanguage)
            )
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
        let languageName = Self.languageName(for: language)
        let prompt = """
        Rephrase the following \(languageName) text at CEFR level \(level.rawValue). \
        Keep meaning intact; use simpler vocabulary and shorter sentences. \
        Output the rephrased text only, no commentary. Output MUST stay in \(languageName).

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
        let languageName = Self.languageName(for: language)
        let prompt = """
        Below are text fragments detected in a single manga page in \(languageName). \
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
