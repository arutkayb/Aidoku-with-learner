//
//  VocabularyListViewModel.swift
//  Aidoku (iOS)
//
//  ObservableObject view model for VocabularyListView.
//  Fetches all vocabulary from CoreData, groups by familiarity level,
//  and supports search filtering and sort ordering.
//

import Foundation
import Combine

// MARK: — Sort option

enum VocabSortOption: String, CaseIterable, Identifiable {
    case dateAddedDesc = "DATE_DESC"
    case dateAddedAsc  = "DATE_ASC"
    case alphabetical  = "ALPHA"
    case familiarityAsc  = "FAM_ASC"
    case familiarityDesc = "FAM_DESC"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .dateAddedDesc:   return NSLocalizedString("LEARNER_SORT_DATE_DESC", comment: "")
        case .dateAddedAsc:    return NSLocalizedString("LEARNER_SORT_DATE_ASC", comment: "")
        case .alphabetical:    return NSLocalizedString("LEARNER_SORT_ALPHA", comment: "")
        case .familiarityAsc:  return NSLocalizedString("LEARNER_SORT_FAM_ASC", comment: "")
        case .familiarityDesc: return NSLocalizedString("LEARNER_SORT_FAM_DESC", comment: "")
        }
    }
}

// MARK: — Vocab section

struct VocabSection: Identifiable {
    let level: Int16      // 0…3, or 99 for "done"
    let title: String
    let entries: [VocabularyEntryObject]
    var id: Int16 { level }
}

// MARK: — VocabularyListViewModel

@MainActor
final class VocabularyListViewModel: ObservableObject {

    @Published var sections: [VocabSection] = []
    @Published var isLoading: Bool = false

    private var allEntries: [VocabularyEntryObject] = []
    private var vocabChangedSubscription: AnyCancellable?

    init() {
        vocabChangedSubscription = LearnerEvents.shared.vocabChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in Task { await self?.refresh() } }
    }

    // MARK: — Data

    func refresh() async {
        isLoading = true
        allEntries = CoreDataManager.shared.getAllVocabulary()
        isLoading = false
    }

    func delete(entry: VocabularyEntryObject) {
        CoreDataManager.shared.removeVocabularyEntry(entry)
        allEntries.removeAll { $0.objectID == entry.objectID }
        LearnerEvents.shared.vocabChanged.send()
    }

    // MARK: — Filtered + sorted sections

    func computedSections(search: String, sort: VocabSortOption) -> [VocabSection] {
        var entries = allEntries

        // Filter
        if !search.isEmpty {
            let q = search.lowercased()
            entries = entries.filter {
                $0.surfaceForm.lowercased().contains(q) ||
                $0.lemma.lowercased().contains(q) ||
                ($0.translation?.lowercased().contains(q) ?? false)
            }
        }

        // Sort
        switch sort {
        case .dateAddedDesc:
            entries.sort { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .dateAddedAsc:
            entries.sort { ($0.dateAdded ?? .distantPast) < ($1.dateAdded ?? .distantPast) }
        case .alphabetical:
            entries.sort { $0.surfaceForm < $1.surfaceForm }
        case .familiarityAsc:
            entries.sort { ($0.progress?.level ?? 0) < ($1.progress?.level ?? 0) }
        case .familiarityDesc:
            entries.sort { ($0.progress?.level ?? 0) > ($1.progress?.level ?? 0) }
        }

        // Group into sections
        let doneEntries = entries.filter { $0.progress?.done == true }
        let activeEntries = entries.filter { $0.progress?.done != true }

        var result: [VocabSection] = []
        for level in Int16(0)...Int16(3) {
            let inLevel = activeEntries.filter { ($0.progress?.level ?? 0) == level }
            if !inLevel.isEmpty {
                result.append(VocabSection(
                    level: level,
                    title: sectionTitle(for: level),
                    entries: inLevel
                ))
            }
        }
        if !doneEntries.isEmpty {
            result.append(VocabSection(
                level: 99,
                title: NSLocalizedString("LEARNER_VOCAB_DONE_SECTION", comment: ""),
                entries: doneEntries
            ))
        }
        return result
    }

    private func sectionTitle(for level: Int16) -> String {
        switch level {
        case 0: return NSLocalizedString("LEARNER_VOCAB_NEW", comment: "")
        case 1: return NSLocalizedString("LEARNER_VOCAB_LEARNING", comment: "")
        case 2: return NSLocalizedString("LEARNER_VOCAB_FAMILIAR", comment: "")
        case 3: return NSLocalizedString("LEARNER_VOCAB_MASTERED", comment: "")
        default: return NSLocalizedString("LEARNER_VOCAB_DONE_SECTION", comment: "")
        }
    }
}
