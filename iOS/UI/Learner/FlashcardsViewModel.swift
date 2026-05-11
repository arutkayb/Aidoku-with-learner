//
//  FlashcardsViewModel.swift
//  Aidoku (iOS)
//
//  ObservableObject view model for FlashcardsView.
//  Manages the flashcard review session: queue loading, card advancement,
//  level updates, and session summary.
//

import Foundation
import Combine

// MARK: — Session summary

struct FlashcardSessionSummary {
    let totalReviewed: Int
    let correctCount: Int
    let newlyMastered: Int
}

// MARK: — FlashcardsViewModel

@MainActor
final class FlashcardsViewModel: ObservableObject {

    // MARK: — State

    @Published var queue: [VocabularyEntryObject] = []
    @Published var currentIndex: Int = 0
    @Published var isFlipped: Bool = false
    @Published var sessionEnded: Bool = false
    @Published var summary: FlashcardSessionSummary?

    private var correctCount: Int = 0
    private var newlyMastered: Int = 0

    static let sessionLimit = 20

    var current: VocabularyEntryObject? {
        guard currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    // MARK: — Load

    func loadQueue() async {
        queue = CoreDataManager.shared.getFlashcardQueue(limit: Self.sessionLimit)
        currentIndex = 0
        isFlipped = false
        correctCount = 0
        newlyMastered = 0
        sessionEnded = queue.isEmpty
        summary = nil
    }

    // MARK: — Card flip

    func flip() {
        isFlipped.toggle()
    }

    // MARK: — Review actions

    func gotIt() async {
        guard let entry = current else { return }
        let prevLevel = entry.progress?.level ?? 0
        CoreDataManager.shared.markFlashcardReview(entry, correct: true)
        correctCount += 1
        if (entry.progress?.level ?? 0) == 3 && prevLevel < 3 {
            newlyMastered += 1
        }
        LearnerEvents.shared.vocabChanged.send()
        advance()
    }

    func stillLearning() async {
        guard let entry = current else { return }
        CoreDataManager.shared.markFlashcardReview(entry, correct: false)
        advance()
    }

    func markDone() async {
        guard let entry = current else { return }
        CoreDataManager.shared.setDone(entry)
        LearnerEvents.shared.vocabChanged.send()
        advance()
    }

    // MARK: — Session control

    func endSession() {
        summary = FlashcardSessionSummary(
            totalReviewed: currentIndex,
            correctCount: correctCount,
            newlyMastered: newlyMastered
        )
        sessionEnded = true
    }

    func restart() async {
        await loadQueue()
    }

    // MARK: — Private

    private func advance() {
        isFlipped = false
        let next = currentIndex + 1
        if next >= queue.count {
            summary = FlashcardSessionSummary(
                totalReviewed: queue.count,
                correctCount: correctCount,
                newlyMastered: newlyMastered
            )
            sessionEnded = true
        } else {
            currentIndex = next
        }
    }
}
