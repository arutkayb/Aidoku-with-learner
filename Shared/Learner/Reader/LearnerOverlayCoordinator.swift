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
    /// Live-text interactions that were detached from the page while Learner was active.
    /// Re-added on `deactivate` / `restoreLiveText`.
    var detachedLiveTextInteractions: [UIInteraction] = []
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

        let key = PageKey(context)
        suppressLiveText(on: container, for: key)

        // If an overlay already exists from a prior load (same page), reuse it.
        let existingOverlay = pageStates[key]?.overlay

        Task {
            guard image.cgImage != nil else { return }

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

            let detached = pageStates[key]?.detachedLiveTextInteractions ?? []
            pageStates[key] = PageState(
                overlay: overlay,
                pageView: container,
                lastOCRResult: result,
                detachedLiveTextInteractions: detached
            )
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
            restoreLiveText(on: container, for: key)
            pageStates.removeValue(forKey: key)
        }
    }

    /// Returns the most recent OCR result for a page, or nil if not yet computed.
    func ocrResult(for context: LearnerPageContext) -> OCRResult? {
        pageStates[PageKey(context)]?.lastOCRResult
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
                        restoreLiveText(on: pv, for: key)
                    }
                }
                pageStates.removeValue(forKey: key)
            }
        }
        // If enabling, the next imageDidLoad call from the page view controller will attach overlays
    }

    // MARK: — Helpers

    private func isLearnerEnabled(for mangaId: String) -> Bool {
        let perManga = UserDefaults.standard.bool(forKey: "Learner.enabled.\(mangaId)")
        let global = UserDefaults.standard.bool(forKey: "Learner.globallyEnabled")
        let enabled = perManga || global
        if enabled && !UserDefaults.standard.bool(forKey: "Learner.enabledGlobally") {
            // First time Learner is active — flip the visibility flag so the
            // Vocabulary tab becomes visible (plan Task 8 Decision #2).
            UserDefaults.standard.set(true, forKey: "Learner.enabledGlobally")
            NotificationCenter.default.post(name: .learnerEnabledGloballyChanged, object: nil)
        }
        return enabled
    }

    private func ocrLanguages() -> [String] {
        // Stored as a single string for now (single-select in settings)
        if let lang = UserDefaults.standard.string(forKey: "Learner.ocrLanguages"), !lang.isEmpty {
            return [lang]
        }
        return ["de-DE"]
    }

    /// Fully detach the live-text interaction while Learner mode is active for `key`.
    /// Hiding `isSupplementaryInterfaceHidden` only hides the button — the underlying
    /// text-selection interaction would still steal long-press touches from the overlay.
    private func suppressLiveText(on container: ReaderPageView, for key: PageKey) {
        guard #available(iOS 16.0, *) else { return }
        var detached: [UIInteraction] = []
        for interaction in container.imageView.interactions {
            if let iai = interaction as? ImageAnalysisInteraction {
                container.imageView.removeInteraction(iai)
                detached.append(iai)
            }
        }
        if !detached.isEmpty, var state = pageStates[key] {
            state.detachedLiveTextInteractions = detached
            pageStates[key] = state
        } else if !detached.isEmpty {
            pageStates[key] = PageState(detachedLiveTextInteractions: detached)
        }
    }

    private func restoreLiveText(on container: ReaderPageView, for key: PageKey? = nil) {
        guard #available(iOS 16.0, *) else { return }
        if let key, let state = pageStates[key] {
            for interaction in state.detachedLiveTextInteractions {
                container.imageView.addInteraction(interaction)
            }
        }
    }
}
#endif // canImport(UIKit)
