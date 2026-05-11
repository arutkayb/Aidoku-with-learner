//
//  VocabIndex.swift
//  Aidoku
//
//  In-memory map of (language, lemma) → FamiliarityLevel, rebuilt on vocabChanged events.
//  Used by LearnerOverlayView to render familiarity badges without hitting CoreData per word.
//

#if canImport(UIKit)
import Combine
import Foundation

/// Familiarity level matching FamiliarityProgress.level in Core Data (0…3) plus a `done` state.
public enum FamiliarityLevel: Int16 {
    case fresh = 0
    case learning = 1
    case familiar = 2
    case mastered = 3
}

/// In-memory index from (language, lemma) to familiarity state.
/// Thread-safe for reads from Main actor (all writes come from CoreDataManager on main context).
@MainActor
public final class VocabIndex {

    public static let shared = VocabIndex()

    private init() {
        rebuild()
        subscribeToChanges()
    }

    // MARK: — Internal storage

    private struct Entry {
        let level: FamiliarityLevel
        let done: Bool
    }

    private var index: [VocabularyEntryObject.Identifier: Entry] = [:]
    private var cancellables: Set<AnyCancellable> = []

    // MARK: — Public interface

    /// Returns the familiarity level for a given (language, lemma) pair, or nil if not in vocab.
    func level(for identifier: VocabularyEntryObject.Identifier) -> FamiliarityLevel? {
        index[identifier]?.level
    }

    /// Returns true if the entry is marked Done.
    func isDone(for identifier: VocabularyEntryObject.Identifier) -> Bool {
        index[identifier]?.done == true
    }

    // MARK: — Rebuild

    /// Rebuilds the index from CoreData. Called on init and on `vocabChanged`.
    public func rebuild() {
        let entries = CoreDataManager.shared.getAllVocabulary()
        var newIndex: [VocabularyEntryObject.Identifier: Entry] = [:]
        newIndex.reserveCapacity(entries.count)
        for entry in entries {
            let identifier = entry.identifier
            let level = FamiliarityLevel(rawValue: entry.progress?.level ?? 0) ?? .fresh
            let done = entry.progress?.done ?? false
            newIndex[identifier] = Entry(level: level, done: done)
        }
        index = newIndex
    }

    // MARK: — Private

    private func subscribeToChanges() {
        LearnerEvents.shared.vocabChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuild()
            }
            .store(in: &cancellables)
    }
}
#endif // canImport(UIKit)
