//
//  DeepLTranslationService.swift
//  Aidoku
//
//  TranslationService implementation using DeepL REST API.
//  Only supports translateWord and translateSentence.
//  simplifyToCEFR and groupFragmentsIntoSentences throw .notSupportedByProvider.
//

import Foundation

/// DeepL-backed translation service. Reads API key from `Learner.deepLAPIKey` UserDefaults key.
/// Supports `translateWord` and `translateSentence` only.
final class DeepLTranslationService: TranslationService {

    /// Injected URLSession — use `.shared` in production; inject a mock in tests.
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: — Private helpers

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "Learner.deepLAPIKey") ?? ""
    }

    private var apiBase: String {
        UserDefaults.standard.string(forKey: "Learner.deepLAPIBase") ?? "https://api-free.deepl.com"
    }

    /// Map an ISO language tag (e.g. "de-DE") to DeepL's source language code ("DE").
    private func deepLSourceLang(_ tag: String) -> String {
        // DeepL source language: 2-letter ISO 639-1 uppercase
        String(tag.prefix(2)).uppercased()
    }

    /// Map an ISO language tag or BCP 47 (e.g. "en", "en-US", "pt-BR") to DeepL's target language code.
    private func deepLTargetLang(_ tag: String) -> String {
        // DeepL accepts "EN-US", "PT-BR" etc. for target; strip and uppercase.
        let parts = tag.components(separatedBy: "-")
        if parts.count >= 2 {
            return (parts[0] + "-" + parts[1]).uppercased()
        }
        return tag.uppercased()
    }

    private func callDeepL(text: String, sourceLang: String, targetLang: String) async throws -> String {
        let key = apiKey
        guard !key.isEmpty else { throw TranslationError.invalidKey }

        let endpoint = apiBase + "/v2/translate"
        guard var components = URLComponents(string: endpoint) else {
            throw TranslationError.unexpectedResponse("Bad DeepL endpoint URL")
        }
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "source_lang", value: deepLSourceLang(sourceLang)),
            URLQueryItem(name: "target_lang", value: deepLTargetLang(targetLang))
        ]
        guard let url = components.url else {
            throw TranslationError.unexpectedResponse("Could not build DeepL request URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // POST body
        let bodyString = "text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text)"
            + "&source_lang=\(deepLSourceLang(sourceLang))"
            + "&target_lang=\(deepLTargetLang(targetLang))"
        request.httpBody = bodyString.data(using: .utf8)
        request.url = URL(string: endpoint)  // Use plain endpoint, body carries params

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 403 {
                    throw TranslationError.invalidKey
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw TranslationError.unexpectedResponse("HTTP \(http.statusCode)")
                }
            }
            // Parse {"translations":[{"text":"...","detected_source_language":"..."}]}
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let translations = json["translations"] as? [[String: Any]],
                let first = translations.first,
                let translated = first["text"] as? String
            else {
                throw TranslationError.unexpectedResponse("Unexpected DeepL response shape")
            }
            return translated
        } catch let err as TranslationError {
            throw err
        } catch {
            print("[Learner] DeepL request failed: \(error)")
            throw TranslationError.networkError(underlying: error)
        }
    }

    // MARK: — TranslationService

    func translateWord(
        _ word: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> WordTranslation {
        let translated = try await callDeepL(text: word, sourceLang: sourceLanguage, targetLang: targetLanguage)
        // DeepL doesn't return part-of-speech or examples; leave them nil.
        return WordTranslation(lemma: word.lowercased(), translation: translated)
    }

    func translateSentence(
        _ sentence: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> SentenceTranslation {
        let translated = try await callDeepL(text: sentence, sourceLang: sourceLanguage, targetLang: targetLanguage)
        return SentenceTranslation(original: sentence, translation: translated)
    }

    func simplifyToCEFR(
        _ sentence: String,
        level: CEFRLevel,
        language: String
    ) async throws -> String {
        throw TranslationError.notSupportedByProvider
    }

    func groupFragmentsIntoSentences(
        _ fragments: [TextFragment],
        language: String
    ) async throws -> [SentenceGroup] {
        throw TranslationError.notSupportedByProvider
    }
}
