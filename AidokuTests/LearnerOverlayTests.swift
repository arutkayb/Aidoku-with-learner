//
//  LearnerOverlayTests.swift
//  Aidoku
//
//  Swift Testing cases for Task 5: LearnerOverlayCoordinator, LearnerOverlayView, VocabIndex.
//

import Foundation
import Testing
@testable import Aidoku

// MARK: — LearnerOverlayView layout tests

@Suite struct LearnerOverlayViewTests {

    // Helpers

    private func makeWords(_ count: Int) -> [OCRWordBox] {
        (0..<count).map { i in
            OCRWordBox(
                text: "Word\(i)",
                boundingBox: CGRect(x: 0.1 * Double(i), y: 0.1, width: 0.08, height: 0.05),
                confidence: 0.95,
                lineIndex: 0
            )
        }
    }

    private func makeContext() -> LearnerPageContext {
        LearnerPageContext(sourceId: "src", mangaId: "manga1", chapterId: "ch1", pageIndex: 0)
    }

    // Test 1: correct number of word region controls are created
    @Test @MainActor func update_createsCorrectNumberOfRegions() {
        let view = LearnerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let words = makeWords(3)
        let vocab = VocabIndex.shared

        view.update(words: words, vocabIndex: vocab, language: "de-DE", pageContext: makeContext())

        // All 3 words should produce subview controls
        #expect(view.subviews.count == 3)
    }

    // Test 2: clear removes all subviews
    @Test @MainActor func clear_removesAllSubviews() {
        let view = LearnerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let words = makeWords(5)

        view.update(words: words, vocabIndex: VocabIndex.shared, language: "de-DE", pageContext: makeContext())
        #expect(view.subviews.count == 5)

        view.clear()
        #expect(view.subviews.isEmpty)
    }

    // Test 3: hit-test passes through on empty overlay space
    @Test @MainActor func hitTest_emptySpace_returnsNil() {
        let view = LearnerOverlayView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        // No words, no controls — tap should pass through
        let hit = view.hitTest(CGPoint(x: 200, y: 300), with: nil)
        #expect(hit == nil)
    }
}

// MARK: — LearnerEvents tests

@Suite struct LearnerEventsTests {

    // Test 4: wordTapped publisher fires
    @Test @MainActor func wordTapped_publisherFires() async {
        let expectationMet = await withCheckedContinuation { continuation in
            var cancellable: (any Sendable)?
            let sub = LearnerEvents.shared.wordTapped
                .first()
                .sink { _ in continuation.resume(returning: true) }
            // Keep subscription alive briefly
            cancellable = sub as? any Sendable
            _ = cancellable

            let ctx = LearnerPageContext(sourceId: "s", mangaId: "m", chapterId: "c", pageIndex: 0)
            let event = WordTapEvent(surfaceForm: "Buch", lemma: "buch", language: "de-DE", pageContext: ctx)
            LearnerEvents.shared.wordTapped.send(event)
        }
        #expect(expectationMet == true)
    }

    // Test 5: vocabChanged publisher fires
    @Test @MainActor func vocabChanged_publisherFires() async {
        let expectationMet = await withCheckedContinuation { continuation in
            var cancellable: (any Sendable)?
            let sub = LearnerEvents.shared.vocabChanged
                .first()
                .sink { _ in continuation.resume(returning: true) }
            cancellable = sub as? any Sendable
            _ = cancellable

            LearnerEvents.shared.vocabChanged.send()
        }
        #expect(expectationMet == true)
    }
}

// MARK: — VocabIndex tests

@Suite struct VocabIndexTests {

    // Test 6: unknown word returns nil level
    @Test @MainActor func level_unknownWord_returnsNil() {
        let index = VocabIndex.shared
        let id = VocabularyEntryObject.Identifier(language: "de-DE", lemma: "unknownxyz123")
        #expect(index.level(for: id) == nil)
    }

    // Test 7: isDone returns false for unknown word
    @Test @MainActor func isDone_unknownWord_returnsFalse() {
        let index = VocabIndex.shared
        let id = VocabularyEntryObject.Identifier(language: "de-DE", lemma: "unknownxyz456")
        #expect(index.isDone(for: id) == false)
    }
}

// MARK: — LearnerCoordinator no-op when disabled

@Suite struct LearnerCoordinatorTests {

    // Test 8: coordinator is a no-op when Learner is disabled for the manga
    @Test @MainActor func imageDidLoad_learnerOff_noOverlay() async {
        let mangaId = "coordinator-test-manga"
        UserDefaults.standard.set(false, forKey: "Learner.enabled.\(mangaId)")

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        let pageView = ReaderPageView()
        pageView.frame = container.bounds

        let ctx = LearnerPageContext(sourceId: "src", mangaId: mangaId, chapterId: "ch1", pageIndex: 0)
        let image = UIImage()

        // Should be a no-op — overlay should NOT be added
        await LearnerOverlayCoordinator.shared.imageDidLoad(image, context: ctx, container: pageView)

        // Give any async tasks a chance to run
        try? await Task.sleep(nanoseconds: 100_000_000)

        let overlayCount = pageView.imageView.subviews.filter { $0 is LearnerOverlayView }.count
        #expect(overlayCount == 0)
    }
}
