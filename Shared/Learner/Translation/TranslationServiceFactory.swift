//
//  TranslationServiceFactory.swift
//  Aidoku
//
//  Singleton factory. Returns a CachingTranslationService wrapping a CompositeTranslationService.
//  Routing is evaluated per-call (not at app launch), so settings changes take effect immediately.
//

import Foundation

final class TranslationServiceFactory: @unchecked Sendable {

    static let shared = TranslationServiceFactory()

    private let _service: CachingTranslationService

    private init() {
        _service = CachingTranslationService(
            wrapping: CompositeTranslationService(),
            countLimit: 500
        )
    }

    /// Returns the configured translation service.
    /// The service re-reads UserDefaults per call, so `Learner.deepLAPIKey` changes are
    /// reflected without restarting the app.
    var service: any TranslationService { _service }
}
