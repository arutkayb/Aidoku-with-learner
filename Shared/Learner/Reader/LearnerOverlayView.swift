//
//  LearnerOverlayView.swift
//  Aidoku
//
//  UIView subclass rendering invisible tappable word regions + familiarity badges
//  over a reader page image.
//
//  Coordinate transform:
//    Vision uses bottom-left origin, normalized [0…1].
//    UIKit uses top-left origin.
//    Transform: viewY = (1 - visionY - visionHeight) * viewHeight
//

#if canImport(UIKit)
import UIKit

/// A transparent view placed as a sibling over ReaderPageView.imageView.
/// Handles:
///  - Per-word tappable UIControl regions
///  - Familiarity badge CAShapeLayer dots on known words
///  - Hit-test passthrough for empty space (chrome-toggle still works)
final class LearnerOverlayView: UIView {

    // MARK: — State

    private var pageContext: LearnerPageContext?
    private var wordBoxes: [OCRWordBox] = []
    private var vocabIndex: VocabIndex = .shared
    private var language: String = "de-DE"

    // MARK: — Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.6
        addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: — Public API

    /// Updates the overlay with a fresh OCR result and vocab index snapshot.
    func update(
        words: [OCRWordBox],
        vocabIndex: VocabIndex,
        language: String,
        pageContext: LearnerPageContext
    ) {
        self.wordBoxes = words
        self.vocabIndex = vocabIndex
        self.language = language
        self.pageContext = pageContext
        rebuild()
    }

    /// Removes all word regions and badges.
    func clear() {
        wordBoxes = []
        pageContext = nil
        rebuild()
    }

    // MARK: — Hit-test passthrough

    /// Only intercept touches on word-region subviews; let everything else fall through.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    // MARK: — Build regions

    private func rebuild() {
        // Remove old regions
        subviews.forEach { $0.removeFromSuperview() }
        layer.sublayers?.filter { $0 is CAShapeLayer }.forEach { $0.removeFromSuperlayer() }

        guard !wordBoxes.isEmpty, bounds.width > 0, bounds.height > 0 else { return }

        let viewSize = bounds.size

        for (index, box) in wordBoxes.enumerated() {
            let frame = visionToView(box.boundingBox, in: viewSize)
            guard frame.width > 2, frame.height > 2 else { continue }

            // Tappable word region
            let control = WordRegionControl(wordBox: box, index: index)
            control.frame = frame
            control.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.25)
            control.layer.cornerRadius = 2
            control.layer.borderWidth = 0.5
            control.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.5).cgColor
            control.addTarget(self, action: #selector(wordTapped(_:)), for: .touchUpInside)
            control.accessibilityLabel = box.text
            addSubview(control)

            // Familiarity badge
            let lemma = VocabularyEntryObject.normalize(box.text)
            let identifier = VocabularyEntryObject.Identifier(language: language, lemma: lemma)
            if let level = vocabIndex.level(for: identifier) {
                let done = vocabIndex.isDone(for: identifier)
                addBadge(to: frame, level: level, done: done)
            }
        }
    }

    // MARK: — Word tap

    @objc private func wordTapped(_ sender: WordRegionControl) {
        guard let pageContext else { return }
        let box = sender.wordBox
        let lemma = VocabularyEntryObject.normalize(box.text)
        let event = WordTapEvent(
            surfaceForm: box.text,
            lemma: lemma,
            language: language,
            pageContext: pageContext
        )
        Task { @MainActor in
            LearnerEvents.shared.wordTapped.send(event)
        }
    }

    // MARK: — Long-press (sentence translate)

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        // If the touch point is inside a word-region control, let the word tap take precedence.
        let point = recognizer.location(in: self)
        for sub in subviews where sub.frame.contains(point) { return }
        Task { @MainActor in
            LearnerEvents.shared.sentenceTranslateRequested.send(nil)
        }
    }

    // MARK: — Badge

    private func addBadge(to frame: CGRect, level: FamiliarityLevel, done: Bool) {
        let badgeSize: CGFloat = 8
        let badgeOrigin = CGPoint(
            x: frame.maxX - badgeSize - 1,
            y: frame.maxY - badgeSize - 1
        )
        let badgeRect = CGRect(origin: badgeOrigin, size: CGSize(width: badgeSize, height: badgeSize))

        let badgeLayer = CAShapeLayer()
        badgeLayer.path = UIBezierPath(ovalIn: badgeRect).cgPath
        badgeLayer.fillColor = badgeColor(for: level, done: done).cgColor
        badgeLayer.strokeColor = UIColor.black.withAlphaComponent(0.3).cgColor
        badgeLayer.lineWidth = 0.5
        layer.addSublayer(badgeLayer)
    }

    private func badgeColor(for level: FamiliarityLevel, done: Bool) -> UIColor {
        if done { return .systemGreen }
        switch level {
        case .fresh:    return .systemGray.withAlphaComponent(0.8)
        case .learning: return .systemYellow
        case .familiar: return .systemOrange
        case .mastered: return .systemGreen
        }
    }

    // MARK: — Coordinate transform

    /// Converts a Vision normalized bounding box (bottom-left origin) to UIKit view coordinates.
    private func visionToView(_ box: CGRect, in size: CGSize) -> CGRect {
        let x = box.origin.x * size.width
        let y = (1.0 - box.origin.y - box.height) * size.height
        let w = box.width * size.width
        let h = box.height * size.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: — WordRegionControl

/// UIControl subclass that holds a reference to its OCRWordBox for tap callbacks.
private final class WordRegionControl: UIControl {
    let wordBox: OCRWordBox
    let wordIndex: Int

    init(wordBox: OCRWordBox, index: Int) {
        self.wordBox = wordBox
        self.wordIndex = index
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif // canImport(UIKit)
