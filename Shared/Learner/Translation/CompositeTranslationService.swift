//
//  CompositeTranslationService.swift
//  Aidoku
//
//  Routes translation calls between DeepL and Foundation Models based on settings.
//  Rules:
//  - translateWord + translateSentence → DeepL if API key is set, else Foundation Models
//  - On DeepL network error → silently fall back to Foundation Models and log
//  - simplifyToCEFR + groupFragmentsIntoSentences → always Foundation Models
//

import Foundation

final class CompositeTranslationService: TranslationService {

    private let foundationModels: any TranslationService
    private let deepL: any TranslationService

    init(
        foundationModels: any TranslationService = FoundationModelsTranslationService(),
        deepL: any TranslationService = DeepLTranslationService()
    ) {
        self.foundationModels = foundationModels
        self.deepL = deepL
    }

    // MARK: — Private

    private var deepLKeyIsSet: Bool {
        let key = UserDefaults.standard.string(forKey: "Learner.deepLAPIKey") ?? ""
        return !key.isEmpty
    }

    // MARK: — TranslationService

    func translateWord(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> WordTranslation {
        if deepLKeyIsSet {
            do {
                return try await deepL.translateWord(word, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            } catch TranslationError.notSupportedByProvider {
                // Should never happen for translateWord, but guard defensively
            } catch {
                print("[Learner] DeepL translateWord failed, falling back to Foundation Models: \(error)")
            }
        }
        return try await foundationModels.translateWord(word, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    }

    func translateSentence(
        _ sentence: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> SentenceTranslation {
        if deepLKeyIsSet {
            do {
                return try await deepL.translateSentence(sentence, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            } catch TranslationError.notSupportedByProvider {
                // Should never happen for translateSentence
            } catch {
                print("[Learner] DeepL translateSentence failed, falling back to Foundation Models: \(error)")
            }
        }
        return try await foundationModels.translateSentence(sentence, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    }

    func simplifyToCEFR(
        _ sentence: String,
        level: CEFRLevel,
        language: String
    ) async throws -> String {
        // Always Foundation Models — DeepL doesn't do simplification
        return try await foundationModels.simplifyToCEFR(sentence, level: level, language: language)
    }

    func groupFragmentsIntoSentences(
        _ fragments: [TextFragment],
        language: String
    ) async throws -> [SentenceGroup] {
        // Always Foundation Models — DeepL doesn't do grouping
        return try await foundationModels.groupFragmentsIntoSentences(fragments, language: language)
    }
}
