//
//  LearnerTabView.swift
//  Aidoku (iOS)
//
//  Top-level container for the Learner tab: two segments, Vocabulary and Flashcards.
//

import SwiftUI

struct LearnerTabView: View {

    @State private var selection: Tab = .vocabulary

    enum Tab {
        case vocabulary, flashcards
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segment picker
                Picker("", selection: $selection) {
                    Text("LEARNER_VOCAB_TAB_TITLE".localized).tag(Tab.vocabulary)
                    Text("LEARNER_FLASHCARDS_TAB_TITLE".localized).tag(Tab.flashcards)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Content
                if selection == .vocabulary {
                    VocabularyListView()
                } else {
                    FlashcardsView()
                }
            }
            .navigationTitle("LEARNER_TAB_TITLE".localized)
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: — Localization

private extension String {
    var localized: String { NSLocalizedString(self, comment: "") }
}
