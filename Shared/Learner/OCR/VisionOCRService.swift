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

final class VisionOCRService: OCRService {

    private let cache: OCRResultCache
    private let queue = DispatchQueue(label: "app.aidoku.learner.ocr", qos: .userInitiated)

    init(cache: OCRResultCache = OCRResultCache()) {
        self.cache = cache
    }

    func recognize(image: UIImage, languages: [String]) async throws -> OCRResult {
        guard let cgImage = image.cgImage else { throw OCRError.imageUnsupported }

        // Cache lookup — hash the PNG data
        guard let pngData = image.pngData() else { throw OCRError.imageUnsupported }
        if let cached = cache.get(imageData: pngData, languages: languages) {
            return cached
        }

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

                    for (lineIndex, obs) in observations.enumerated() {
                        guard let candidate = obs.topCandidates(1).first else { continue }

                        let lineText = candidate.string
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
                                text: String(token),
                                boundingBox: wordBoundingBox,
                                confidence: obs.confidence,
                                lineIndex: lineIndex
                            ))
                        }
                    }

                    continuation.resume(returning: OCRResult(words: words, lines: lines))
                }

                request.recognitionLevel = .accurate
                request.recognitionLanguages = languages
                request.usesLanguageCorrection = true

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
}
#endif // canImport(UIKit)
