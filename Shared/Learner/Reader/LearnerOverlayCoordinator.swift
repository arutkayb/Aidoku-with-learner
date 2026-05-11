//
//  LearnerOverlayCoordinator.swift
//  Aidoku
//
//  @MainActor singleton that manages per-page LearnerOverlayViews.
//  Called from ReaderPageView after image assignment and from ReaderPagedViewController
//  on page-change events.
//

#if canImport(UIKit)
import UIKit
import VisionKit

/// Key uniquely identifying one reader page.
private struct PageKey: Hashable {
    let sourceId: String
    let mangaId: String
    let chapterId: String
    let pageIndex: Int

    init(_ ctx: LearnerPageContext) {
        sourceId = ctx.sourceId
        mangaId = ctx.mangaId
        chapterId = ctx.chapterId
        pageIndex = ctx.pageIndex
    }
}

/// Tracks overlay state for a single page.
private struct PageState {
    weak var overlay: LearnerOverlayView?
    weak var pageView: ReaderPageView?
    var lastOCRResult: OCRResult?
}

@MainActor
final class LearnerOverlayCoordinator {

    static let shared = LearnerOverlayCoordinator()

    private init() {}

    private let ocr: OCRService = VisionOCRService()
    private var pageStates: [PageKey: PageState] = [:]

    // MARK: — Public API

    /// Call this from ReaderPageView after `imageView.image = image`.
    func imageDidLoad(_ image: UIImage, context: LearnerPageContext, container: ReaderPageView) {
        let mangaId = context.mangaId
        guard isLearnerEnabled(for: mangaId) else {
            deactivate(for: context, container: container)
            return
        }

        suppressLiveText(on: container)

        let key = PageKey(context)
        // If an overlay already exists from a prior load (same page), reuse it.
        let existingOverlay = pageStates[key]?.overlay

        Task {
            guard let cgImage = image.cgImage else { return }
            _ = cgImage // suppress unused warning

            let languages = ocrLanguages()
            let result: OCRResult
            do {
                result = try await ocr.recognize(image: image, languages: languages)
            } catch {
                return
            }

            // Attach (or reuse) overlay
            let overlay: LearnerOverlayView
            if let existing = existingOverlay, existing.superview != nil {
                overlay = existing
            } else {
                overlay = LearnerOverlayView()
                overlay.translatesAutoresizingMaskIntoConstraints = false
                container.imageView.addSubview(overlay)
                NSLayoutConstraint.activate([
                    overlay.topAnchor.constraint(equalTo: container.imageView.topAnchor),
                    overlay.leadingAnchor.constraint(equalTo: container.imageView.leadingAnchor),
                    overlay.trailingAnchor.constraint(equalTo: container.imageView.trailingAnchor),
                    overlay.bottomAnchor.constraint(equalTo: container.imageView.bottomAnchor)
                ])
            }

            overlay.update(
                words: result.words,
                vocabIndex: .shared,
                language: languages.first ?? "de-DE",
                pageContext: context
            )

            pageStates[key] = PageState(overlay: overlay, pageView: container, lastOCRResult: result)
        }
    }

    /// Call this when a page becomes visible after a swipe (to refresh badges).
    func pageDidBecomeVisible(context: LearnerPageContext, container: ReaderPageView) {
        guard isLearnerEnabled(for: context.mangaId) else { return }
        let key = PageKey(context)
        guard let state = pageStates[key], let overlay = state.overlay, let result = state.lastOCRResult else {
            // No cached result; trigger a fresh OCR if image is available
            if let image = container.imageView.image {
                imageDidLoad(image, context: context, container: container)
            }
            return
        }
        // Refresh badges with updated vocab index
        overlay.update(
            words: result.words,
            vocabIndex: .shared,
            language: ocrLanguages().first ?? "de-DE",
            pageContext: context
        )
    }

    /// Removes overlay for a page (called when Learner is toggled off).
    func deactivate(for context: LearnerPageContext, container: ReaderPageView) {
        let key = PageKey(context)
        if let state = pageStates[key] {
            state.overlay?.removeFromSuperview()
            pageStates.removeValue(forKey: key)
        }
        restoreLiveText(on: container)
    }

    /// Called when the global Learner toggle changes for a manga.
    func setEnabled(_ enabled: Bool, for mangaId: String) {
        if !enabled {
            // Remove all overlays for this manga
            let keysToRemove = pageStates.keys.filter { $0.mangaId == mangaId }
            for key in keysToRemove {
                if let state = pageStates[key] {
                    state.overlay?.removeFromSuperview()
                    if let pv = state.pageView {
                        restoreLiveText(on: pv)
                    }
                }
                pageStates.removeValue(forKey: key)
            }
        }
        // If enabling, the next imageDidLoad call from the page view controller will attach overlays
    }

    // MARK: — Helpers

    private func isLearnerEnabled(for mangaId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "Learner.enabled.\(mangaId)")
    }

    private func ocrLanguages() -> [String] {
        // Stored as a single string for now (single-select in settings)
        if let lang = UserDefaults.standard.string(forKey: "Learner.ocrLanguages"), !lang.isEmpty {
            return [lang]
        }
        return ["de-DE"]
    }

    private func suppressLiveText(on container: ReaderPageView) {
        if #available(iOS 16.0, *) {
            for interaction in container.imageView.interactions {
                if let iai = interaction as? ImageAnalysisInteraction {
                    iai.isSupplementaryInterfaceHidden = true
                }
            }
        }
    }

    private func restoreLiveText(on container: ReaderPageView) {
        if #available(iOS 16.0, *) {
            for interaction in container.imageView.interactions {
                if let iai = interaction as? ImageAnalysisInteraction {
                    iai.isSupplementaryInterfaceHidden = false
                }
            }
        }
    }
}
#endif // canImport(UIKit)
