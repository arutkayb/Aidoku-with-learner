//
//  LearnerEvents.swift
//  Aidoku
//
//  Central event hub for Learner mode.
//  All publishers are PassthroughSubjects dispatched on the main actor.
//

#if canImport(UIKit)
import Combine
import Foundation
import UIKit

/// Carries the data emitted when the user taps a word region in the overlay.
public struct WordTapEvent: Sendable {
    /// The word text as recognized by OCR (surface form).
    public let surfaceForm: String
    /// Inferred lemma (normalized surface form).
    public let lemma: String
    /// BCP-47 language tag for the word, e.g. "de-DE".
    public let language: String
    /// Page context where the tap occurred.
    public let pageContext: LearnerPageContext

    public init(surfaceForm: String, lemma: String, language: String, pageContext: LearnerPageContext) {
        self.surfaceForm = surfaceForm
        self.lemma = lemma
        self.language = language
        self.pageContext = pageContext
    }
}

/// Identifies a specific page in the reader.
public struct LearnerPageContext: Sendable, Hashable {
    public let sourceId: String
    public let mangaId: String
    public let chapterId: String
    public let pageIndex: Int

    public init(sourceId: String, mangaId: String, chapterId: String, pageIndex: Int) {
        self.sourceId = sourceId
        self.mangaId = mangaId
        self.chapterId = chapterId
        self.pageIndex = pageIndex
    }
}

/// Shared event hub for Learner mode.
/// All subjects publish on the main thread.
@MainActor
public final class LearnerEvents {

    public static let shared = LearnerEvents()

    private init() {}

    /// Fired when the user taps a recognized word region.
    public let wordTapped = PassthroughSubject<WordTapEvent, Never>()

    /// Fired when a sentence-translation is requested (from word sheet or long-press).
    /// `WordTapEvent?` is non-nil when triggered from a word lookup sheet.
    public let sentenceTranslateRequested = PassthroughSubject<WordTapEvent?, Never>()

    /// Fired when the vocabulary list changes (entry added/removed/familiarity changed).
    /// Subscribers (overlay, vocab list) should refresh their vocab index on receipt.
    public let vocabChanged = PassthroughSubject<Void, Never>()
}
#endif // canImport(UIKit)
