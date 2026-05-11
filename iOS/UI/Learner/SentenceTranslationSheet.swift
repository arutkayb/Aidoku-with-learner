//
//  SentenceTranslationSheet.swift
//  Aidoku (iOS)
//
//  Bottom sheet presenting sentence-level translation for a manga page.
//  Sentences are grouped via Foundation Models and translated in parallel.
//  Each row expands to show a CEFR-simplified version on demand.
//

import SwiftUI

struct SentenceTranslationSheet: View {

    @StateObject private var viewModel: SentenceTranslationViewModel
    private let chapterTitle: String
    private let pageNumber: Int

    init(
        context: LearnerPageContext,
        ocrResult: OCRResult,
        focusLemma: String? = nil,
        chapterTitle: String,
        pageNumber: Int
    ) {
        self._viewModel = StateObject(
            wrappedValue: SentenceTranslationViewModel(
                context: context,
                ocrResult: ocrResult,
                focusLemma: focusLemma
            )
        )
        self.chapterTitle = chapterTitle
        self.pageNumber = pageNumber
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.loadError {
                    errorView(error)
                } else if viewModel.sentences.isEmpty {
                    emptyView
                } else {
                    sentenceList
                }
            }
            .navigationTitle(headerTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .task { await viewModel.load() }
    }

    // MARK: — Header

    private var headerTitle: String {
        "\(chapterTitle) · \("LEARNER_PAGE".localized) \(pageNumber)"
    }

    // MARK: — Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("LOADING_ELLIPSIS".localized)
                .foregroundStyle(.secondary)
                .font(.body)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Error

    private func errorView(_ error: TranslationError) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("LEARNER_SENTENCE_LOAD_ERROR".localized)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("LEARNER_RETRY".localized) {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("LEARNER_NO_TEXT_DETECTED".localized)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Sentence list

    private var sentenceList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach($viewModel.sentences) { $sentence in
                        SentenceRowView(sentence: $sentence) {
                            Task { await viewModel.simplify(id: sentence.id) }
                        }
                        Divider()
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                if let lemma = viewModel.focusLemma,
                   let target = viewModel.sentences.first(where: { $0.source.localizedCaseInsensitiveContains(lemma) }) {
                    proxy.scrollTo(target.id, anchor: .top)
                }
            }
        }
    }
}

// MARK: — SentenceRowView

private struct SentenceRowView: View {

    @Binding var sentence: SentenceVM
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Source text
            Text(sentence.source)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            // Translation (or loading dots if still pending)
            if let translation = sentence.translation {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("···")
                    .foregroundStyle(.tertiary)
                    .font(.body)
            }

            // Simplification disclosure
            DisclosureGroup(
                isExpanded: Binding(
                    get: { sentence.simplifyExpanded },
                    set: { expanded in
                        sentence.simplifyExpanded = expanded
                        if expanded && sentence.simplified == nil && sentence.simplifyError == nil {
                            onExpand()
                        }
                    }
                )
            ) {
                Group {
                    if let simplified = sentence.simplified {
                        Text(simplified)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let errorMsg = sentence.simplifyError {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("LEARNER_SIMPLIFIED_LABEL".localized)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: — Localization

private extension String {
    var localized: String { NSLocalizedString(self, comment: "") }
}
