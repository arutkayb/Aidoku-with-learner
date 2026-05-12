//
//  VisionOCRService.swift
//  Aidoku
//
//  Concrete OCRService implementation using VNRecognizeTextRequest (Vision framework).
//  Runs on a dedicated background queue; never blocks the main thread.
//  iOS-only (Vision's text recognition depends on UIKit image types on iOS).
//

#if canImport(UIKit)
import Foundation
import Vision
import UIKit
import CoreImage

final class VisionOCRService: OCRService {

    /// Manga pages from many sources arrive at ~800-1200px wide. Vision's text-detection
    /// stage is pixel-size sensitive: hand-lettered short rows ("ER", "SO", "DA-") get
    /// dropped before recognition even runs. We upscale anything below this width to
    /// give detection enough pixels — empirically matches the resolution at which iOS
    /// Photos' built-in OCR succeeds on the same source images.
    private static let minOCRWidth: CGFloat = 2400

    private let cache: OCRResultCache
    private let queue = DispatchQueue(label: "app.aidoku.learner.ocr", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(cache: OCRResultCache = OCRResultCache()) {
        self.cache = cache
    }

    func recognize(image: UIImage, languages: [String]) async throws -> OCRResult {
        guard let originalCGImage = image.cgImage else { throw OCRError.imageUnsupported }

        // Cache lookup — hash the PNG data (use the original, not the upscaled version,
        // so cache keys stay stable when the upscale threshold is tuned).
        guard let pngData = image.pngData() else { throw OCRError.imageUnsupported }
        if let cached = cache.get(imageData: pngData, languages: languages) {
            return cached
        }

        let cgImage = upscaledForOCR(originalCGImage) ?? originalCGImage

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OCRResult, Error>) in
            queue.async {
                assert(!Thread.isMainThread, "OCR must not run on main thread")

                let request = VNRecognizeTextRequest { req, error in
                    if let error {
                        continuation.resume(throwing: OCRError.requestFailed(error))
                        return
                    }
                    guard let observations = req.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: OCRResult(words: [], lines: []))
                        return
                    }

                    var lines: [OCRLineBox] = []
                    var words: [OCRWordBox] = []

                    // Filters for high-res false positives (screentone, sound effects,
                    // decorative strokes). Tuned empirically against German manga lettering;
                    // real text comfortably clears 0.5 on revision 3, noise sits below 0.3.
                    let minObservationConfidence: VNConfidence = 0.4
                    let letterSet = CharacterSet.letters
                    func containsLetter(_ s: String) -> Bool {
                        s.unicodeScalars.contains(where: { letterSet.contains($0) })
                    }

                    for (lineIndex, obs) in observations.enumerated() {
                        guard obs.confidence >= minObservationConfidence else { continue }
                        guard let candidate = obs.topCandidates(1).first else { continue }

                        let lineText = candidate.string
                        guard containsLetter(lineText) else { continue }
                        let lineBox = OCRLineBox(
                            text: lineText,
                            boundingBox: obs.boundingBox,
                            confidence: obs.confidence
                        )
                        lines.append(lineBox)

                        // Per-word boxes using boundingBox(for:range)
                        let tokens = lineText.split(separator: " ", omittingEmptySubsequences: true)
                        var searchStart = lineText.startIndex
                        for token in tokens {
                            let tokenString = String(token)
                            guard containsLetter(tokenString) else { continue }
                            guard let tokenRange = lineText.range(of: token, range: searchStart..<lineText.endIndex) else {
                                continue
                            }
                            searchStart = tokenRange.upperBound

                            let wordBoundingBox: CGRect
                            if let wordObs = try? candidate.boundingBox(for: tokenRange) {
                                wordBoundingBox = wordObs.boundingBox
                            } else {
                                // Fallback: use the line box for this word
                                wordBoundingBox = obs.boundingBox
                            }
                            words.append(OCRWordBox(
                                text: tokenString,
                                boundingBox: wordBoundingBox,
                                confidence: obs.confidence,
                                lineIndex: lineIndex
                            ))
                        }
                    }

                    // Merge hyphenated words that wrap across lines.
                    // Example: "ABEND-" on line N and "ESSEN" on line N+1 become "ABENDESSEN".
                    // The merged word keeps the bounding box of the first half (the upper one)
                    // so the tap target sits where the user expects.
                    //
                    // Cascades for 3+ piece splits ("VER-/BRENN-/UNGEN"): the merged token
                    // adopts the *second* half's lineIndex so the next iteration can chain.
                    //
                    // Recognises multiple dash codepoints — Vision sometimes emits U+2010,
                    // U+2013, U+00AD instead of plain ASCII hyphen-minus.
                    let trailingDashes: [Character] = ["-", "\u{2010}", "\u{2011}", "\u{2013}", "\u{2014}", "\u{00AD}"]
                    func endsWithDash(_ s: String) -> Bool {
                        guard let last = s.last else { return false }
                        return trailingDashes.contains(last)
                    }
                    var mergedWords: [OCRWordBox] = []
                    var i = 0
                    while i < words.count {
                        let current = words[i]
                        if endsWithDash(current.text),
                           i + 1 < words.count,
                           words[i + 1].lineIndex == current.lineIndex + 1 {
                            let next = words[i + 1]
                            let stem = String(current.text.dropLast()) // drop trailing dash
                            let merged = OCRWordBox(
                                text: stem + next.text,
                                boundingBox: current.boundingBox,
                                confidence: min(current.confidence, next.confidence),
                                lineIndex: next.lineIndex
                            )
                            mergedWords.append(merged)
                            i += 2
                        } else {
                            mergedWords.append(current)
                            i += 1
                        }
                    }
                    // Second pass: chains can leave a tail like "VERBRENN-" (still ending in
                    // a dash) immediately followed by the next-line tail. Re-run until
                    // no more merges happen. Bounded by `mergedWords.count` iterations.
                    var converged = false
                    var safety = mergedWords.count
                    while !converged && safety > 0 {
                        safety -= 1
                        converged = true
                        var pass: [OCRWordBox] = []
                        var j = 0
                        while j < mergedWords.count {
                            let current = mergedWords[j]
                            if endsWithDash(current.text),
                               j + 1 < mergedWords.count,
                               mergedWords[j + 1].lineIndex == current.lineIndex + 1 {
                                let next = mergedWords[j + 1]
                                let stem = String(current.text.dropLast())
                                pass.append(OCRWordBox(
                                    text: stem + next.text,
                                    boundingBox: current.boundingBox,
                                    confidence: min(current.confidence, next.confidence),
                                    lineIndex: next.lineIndex
                                ))
                                j += 2
                                converged = false
                            } else {
                                pass.append(current)
                                j += 1
                            }
                        }
                        mergedWords = pass
                    }
                    continuation.resume(returning: OCRResult(words: mergedWords, lines: lines))
                }

                request.recognitionLevel = .accurate
                request.recognitionLanguages = languages
                // Task 7: allow disabling language correction to fix umlaut mangling
                // e.g. "ÜBERTROFFEN" → "BERTROFFEN" with correction on.
                let disableCorrection = UserDefaults.standard.bool(forKey: "Learner.disableLanguageCorrection")
                request.usesLanguageCorrection = !disableCorrection
                // Vision's default detection heuristic drops short stacked lines like
                // "ER" / "HÄTTE" / "SO" in narrow manga bubbles. Force the floor to 0
                // so every detected region is attempted.
                request.minimumTextHeight = 0
                // Pin to the modern Vision text engine; older revisions misbehave on
                // fragmented hand-lettered text.
                if #available(iOS 16.0, *) {
                    if VNRecognizeTextRequest.supportedRevisions.contains(VNRecognizeTextRequestRevision3) {
                        request.revision = VNRecognizeTextRequestRevision3
                    }
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.requestFailed(error))
                }
            }
        }

        cache.put(imageData: pngData, languages: languages, result: result)
        return result
    }

    /// Returns a Lanczos-upscaled CGImage if the source is narrower than `minOCRWidth`,
    /// or nil if no upscale is needed / the upscale fails (caller falls back to the
    /// original). Vision normalizes bounding boxes to [0,1], so overlay coordinates
    /// remain correct regardless of which pixel size we OCR.
    private func upscaledForOCR(_ source: CGImage) -> CGImage? {
        let width = CGFloat(source.width)
        guard width > 0, width < Self.minOCRWidth else { return nil }
        let scale = Self.minOCRWidth / width
        let ciImage = CIImage(cgImage: source)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }
}
#endif // canImport(UIKit)
