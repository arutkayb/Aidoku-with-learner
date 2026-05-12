//
//  VocabularyListView.swift
//  Aidoku (iOS)
//
//  Vocabulary list grouped by familiarity level.
//  Tap a row to open WordLookupSheet in vocab-only mode.
//  Swipe-to-delete removes the entry from CoreData.
//

import SwiftUI

struct VocabularyListView: View {

    @StateObject private var viewModel = VocabularyListViewModel()
    @State private var search: String = ""
    @State private var sort: VocabSortOption = .dateAddedDesc
    @State private var selectedEntry: VocabularyEntryObject?

    var body: some View {
        let sections = viewModel.computedSections(search: search, sort: sort)

        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sections.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sections) { section in
                        Section(header: Text(section.title)) {
                            ForEach(section.entries, id: \.objectID) { entry in
                                VocabRowView(entry: entry)
                                    .onTapGesture { selectedEntry = entry }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            viewModel.delete(entry: entry)
                                        } label: {
                                            Label("DELETE".localized, systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("LEARNER_VOCAB_TAB_TITLE".localized)
        .searchable(text: $search, prompt: "LEARNER_VOCAB_SEARCH".localized)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(VocabSortOption.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            if sort == option {
                                Label(option.localizedTitle, systemImage: "checkmark")
                            } else {
                                Text(option.localizedTitle)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            WordLookupSheet(entry: entry)
        }
        .task { await viewModel.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("LEARNER_VOCAB_EMPTY".localized)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: — VocabRowView

private struct VocabRowView: View {
    let entry: VocabularyEntryObject

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(familiarityColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.surfaceForm)
                    .font(.body.bold())
                if entry.lemma != entry.surfaceForm.lowercased() {
                    Text(entry.lemma)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let translation = entry.translation {
                    Text(translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let notes = entry.notes, !notes.isEmpty {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let mangaId = entry.sourceMangaId, !mangaId.isEmpty {
                Text(mangaId)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    private var familiarityColor: Color {
        if entry.progress?.done == true { return .green }
        switch entry.progress?.level ?? 0 {
        case 0: return .gray
        case 1: return .yellow
        case 2: return .orange
        case 3: return .green
        default: return .gray
        }
    }
}

// MARK: — VocabularyEntryObject: Identifiable for sheet(item:)

extension VocabularyEntryObject: Identifiable {}

// MARK: — Localization

private extension String {
    var localized: String { NSLocalizedString(self, comment: "") }
}
