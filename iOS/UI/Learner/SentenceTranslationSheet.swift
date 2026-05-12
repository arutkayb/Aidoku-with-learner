//
//  SentenceTranslationSheet.swift
//  Aidoku (iOS)
//
//  Bottom sheet presenting sentence-level translation for a manga page.
//  Sentences are grouped via Foundation Models and translated in parallel.
//  Each row expands to show a CEFR-simplified version on demand.
//

import SwiftUI
#if canImport(Translation)
import Translation
#endif

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
        .modifier(SentenceTranslationDriver(viewModel: viewModel))
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

    @State private var highlightedId: UUID?

    private var sentenceList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach($viewModel.sentences) { $sentence in
                        SentenceRowView(
                            sentence: $sentence,
                            language: viewModel.context.language,
                            pageContext: viewModel.context,
                            isHighlighted: highlightedId == sentence.id
                        ) {
                            Task { await viewModel.simplify(id: sentence.id) }
                        }
                        Divider()
                    }
                }
                .padding(.vertical, 8)
            }
            .task(id: viewModel.sentences.count) {
                // Re-trigger when sentences arrive (they populate asynchronously).
                guard let lemma = viewModel.focusLemma, !viewModel.sentences.isEmpty else { return }
                let normalised = lemma.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if let target = viewModel.sentences.first(where: {
                    $0.source.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        .contains(normalised)
                }) {
                    withAnimation { proxy.scrollTo(target.id, anchor: .center) }
                    highlightedId = target.id
                    // Fade the highlight after 1.5 s
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation(.easeOut(duration: 0.5)) { highlightedId = nil }
                }
            }
        }
    }
}

// MARK: — Tokenized word for tap handling

private struct SentenceToken: Identifiable {
    let id = UUID()
    let text: String
}

private func tokenize(_ sentence: String) -> [SentenceToken] {
    sentence
        .split(whereSeparator: { $0.isWhitespace })
        .map { SentenceToken(text: String($0)) }
}

// MARK: — SentenceRowView

private struct SentenceRowView: View {

    @Binding var sentence: SentenceVM
    let language: String
    let pageContext: LearnerPageContext
    var isHighlighted: Bool = false
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Source text — per-word taps emit `wordTapped` so the same WordLookupSheet
            // flow as in the reader is reused (plan Task 7 AC #4).
            WrappingHStack(tokenize(sentence.source), id: \.id) { token in
                Button {
                    let event = WordTapEvent(
                        surfaceForm: token.text,
                        lemma: LearnerStrings.normalizeLemma(token.text),
                        language: language,
                        pageContext: pageContext
                    )
                    LearnerEvents.shared.wordTapped.send(event)
                } label: {
                    Text(token.text + " ")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
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
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .animation(.easeOut(duration: 0.5), value: isHighlighted)
    }
}

// MARK: — Localization

private extension String {
    var localized: String { NSLocalizedString(self, comment: "") }
}

// MARK: — Translation driver

/// Mirrors the WordLookupSheet pattern: uses Apple Translation on iOS 18+,
/// falls back to the composite service below.
private struct SentenceTranslationDriver: ViewModifier {
    @ObservedObject var viewModel: SentenceTranslationViewModel

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            content.modifier(AppleSentenceTranslationModifier(viewModel: viewModel))
        } else {
            content.task { await viewModel.load() }
        }
        #else
        content.task { await viewModel.load() }
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct AppleSentenceTranslationModifier: ViewModifier {
    @ObservedObject var viewModel: SentenceTranslationViewModel
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .task {
                await viewModel.loadSourceSentences()
                guard configuration == nil else { return }
                let target = UserDefaults.standard.string(forKey: "Learner.targetLanguage") ?? "en"
                let sourceCode = String(viewModel.context.language.prefix(2))
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: sourceCode),
                    target: Locale.Language(identifier: target)
                )
            }
            .translationTask(configuration) { session in
                await viewModel.translateAll(using: session)
            }
    }
}
#endif
