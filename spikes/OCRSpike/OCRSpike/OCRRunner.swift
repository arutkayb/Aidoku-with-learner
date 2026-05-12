//
//  OCRRunner.swift
//  OCRSpike
//
//  Wraps VNRecognizeTextRequest and returns per-word bounding boxes
//  in normalized image coordinates (0…1, bottom-left origin — Vision native).
//

import Vision
import UIKit

/// A single recognized word with its bounding box.
struct WordBox: Identifiable {
    let id = UUID()
    /// The recognized text token (one whitespace-separated word).
    let text: String
    /// Normalized bounding rect in Vision coord space: origin bottom-left, values 0…1.
    let rect: CGRect
    /// Confidence from the parent observation.
    let confidence: Float
}

/// A full line of recognized text with its bounding box.
struct LineBox: Identifiable {
    let id = UUID()
    let text: String
    let rect: CGRect
    let confidence: Float
}

struct OCRRunner {

    enum OCRLevel {
        case word
        case line
    }

    /// Runs VNRecognizeTextRequest on the given image synchronously on a background queue.
    /// Returns word boxes (Vision native coords: bottom-left origin, 0…1).
    /// - Parameters:
    ///   - image: The manga page image.
    ///   - language: BCP-47 language tag, e.g. "de-DE".
    ///   - level: Word-level or line-level boxes.
    func recognizeWords(
        in image: UIImage,
        language: String = "de-DE",
        level: OCRLevel = .word
    ) async throws -> ([WordBox], [LineBox]) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = image.cgImage else {
                    continuation.resume(throwing: OCRError.invalidImage)
                    return
                }
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = [language]
                request.usesLanguageCorrection = true
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.requestFailed(error))
                    return
                }
                guard let results = request.results else {
                    continuation.resume(returning: ([], []))
                    return
                }
                var wordBoxes: [WordBox] = []
                var lineBoxes: [LineBox] = []
                for obs in results {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    let lineText = candidate.string
                    lineBoxes.append(LineBox(
                        text: lineText,
                        rect: obs.boundingBox,
                        confidence: obs.confidence
                    ))
                    // Per-word boxes via range-based API
                    let tokens = lineText.split(separator: " ", omittingEmptySubsequences: true)
                    var searchStart = lineText.startIndex
                    for token in tokens {
                        let tokenStr = String(token)
                        guard let tokenRange = lineText.range(of: tokenStr, range: searchStart..<lineText.endIndex) else {
                            continue
                        }
                        searchStart = tokenRange.upperBound
                        if let wordObs = try? candidate.boundingBox(for: tokenRange) {
                            wordBoxes.append(WordBox(
                                text: tokenStr,
                                rect: wordObs.boundingBox,
                                confidence: obs.confidence
                            ))
                        } else {
                            // Fallback to line box for this token
                            wordBoxes.append(WordBox(
                                text: tokenStr,
                                rect: obs.boundingBox,
                                confidence: obs.confidence
                            ))
                        }
                    }
                }
                continuation.resume(returning: (wordBoxes, lineBoxes))
            }
        }
    }
}

enum OCRError: Error {
    case invalidImage
    case requestFailed(Error)
}
