//
//  FlashcardsView.swift
//  Aidoku (iOS)
//
//  Flashcard review mode.
//  Tap the card to flip it. "Got it" raises level; "Still learning" keeps it.
//  Shows a session summary when all cards have been reviewed.
//

import SwiftUI

struct FlashcardsView: View {

    @StateObject private var viewModel = FlashcardsViewModel()

    var body: some View {
        Group {
            if viewModel.sessionEnded {
                if let summary = viewModel.summary {
                    summaryView(summary)
                } else {
                    emptyView
                }
            } else if let entry = viewModel.current {
                cardView(entry: entry)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("LEARNER_FLASHCARDS_TAB_TITLE".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadQueue() }
    }

    // MARK: — Card

    private func cardView(entry: VocabularyEntryObject) -> some View {
        VStack(spacing: 24) {
            // Progress
            Text("\(viewModel.currentIndex + 1) / \(viewModel.queue.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Card
            ZStack {
                frontFace(entry: entry)
                    .opacity(viewModel.isFlipped ? 0 : 1)
                backFace(entry: entry)
                    .opacity(viewModel.isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .rotation3DEffect(
                .degrees(viewModel.isFlipped ? 180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
            .animation(.spring(duration: 0.4), value: viewModel.isFlipped)
            .onTapGesture { viewModel.flip() }
            .padding(.horizontal)

            // Tap hint
            if !viewModel.isFlipped {
                Text("LEARNER_FC_TAP_TO_FLIP".localized)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Action buttons (only on back)
            if viewModel.isFlipped {
                HStack(spacing: 16) {
                    Button {
                        Task { await viewModel.stillLearning() }
                    } label: {
                        Label("LEARNER_FC_STILL_LEARNING".localized, systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button {
                        Task { await viewModel.gotIt() }
                    } label: {
                        Label("LEARNER_FC_GOT_IT".localized, systemImage: "hand.thumbsup")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(.horizontal)

                Button {
                    Task { await viewModel.markDone() }
                } label: {
                    Label("LEARNER_FC_MARK_DONE".localized, systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .padding(.horizontal)
            }

            // End session
            Button("LEARNER_FC_END_SESSION".localized) {
                viewModel.endSession()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: — Card faces

    private func frontFace(entry: VocabularyEntryObject) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                VStack(spacing: 8) {
                    Text(entry.surfaceForm)
                        .font(.largeTitle.bold())
                    if entry.lemma != entry.surfaceForm.lowercased() {
                        Text(entry.lemma)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            )
            .frame(height: 200)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    private func backFace(entry: VocabularyEntryObject) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                VStack(spacing: 10) {
                    if let translation = entry.translation {
                        Text(translation)
                            .font(.title2.bold())
                    } else {
                        Text("LEARNER_NO_TRANSLATION".localized)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.lemma)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding()
            )
            .frame(height: 200)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: — Empty state

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("LEARNER_FC_EMPTY".localized)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Summary

    private func summaryView(_ summary: FlashcardSessionSummary) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "star.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("LEARNER_FC_SUMMARY_TITLE".localized)
                .font(.title2.bold())

            VStack(spacing: 12) {
                summaryRow(
                    label: "LEARNER_FC_SUMMARY_REVIEWED".localized,
                    value: "\(summary.totalReviewed)"
                )
                summaryRow(
                    label: "LEARNER_FC_SUMMARY_CORRECT".localized,
                    value: "\(summary.correctCount)"
                )
                summaryRow(
                    label: "LEARNER_FC_SUMMARY_MASTERED".localized,
                    value: "\(summary.newlyMastered)"
                )
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            Button("LEARNER_FC_RESTART".localized) {
                Task { await viewModel.restart() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
    }
}

// MARK: — Localization

private extension String {
    var localized: String { NSLocalizedString(self, comment: "") }
}
