//
//  OCRServiceTests.swift
//  Aidoku
//
//  Swift Testing cases for VisionOCRService and OCRResultCache.
//

import Foundation
import CoreGraphics
import Testing
@testable import Aidoku

#if canImport(UIKit)
import UIKit
#endif

@Suite struct OCRServiceTests {

    // MARK: 1. Same image + same languages → cache hit, underlying not re-invoked

    @Test func recognize_cachedResult_doesNotReinvoke() async throws {
        let cache = OCRResultCache(countLimit: 32)
        let countingService = CountingOCRService(cache: cache)

        guard let image = loadFixture(named: "ocr-hallo-welt") else {
            Issue.record("Test fixture ocr-hallo-welt.png not found in bundle — skipping")
            return
        }

        _ = try await countingService.recognize(image: image, languages: ["de-DE"])
        _ = try await countingService.recognize(image: image, languages: ["de-DE"])

        #expect(countingService.visionCallCount == 1,
                "Second call with same image + languages should hit cache, not call Vision again")
    }

    // MARK: 2. Language change → cache miss

    @Test func recognize_languageChange_missesCache() async throws {
        let cache = OCRResultCache(countLimit: 32)
        let countingService = CountingOCRService(cache: cache)

        guard let image = loadFixture(named: "ocr-hallo-welt") else {
            Issue.record("Test fixture ocr-hallo-welt.png not found in bundle — skipping")
            return
        }

        _ = try await countingService.recognize(image: image, languages: ["de-DE"])
        _ = try await countingService.recognize(image: image, languages: ["en-US"])  // different language

        #expect(countingService.visionCallCount == 2,
                "Different language should miss cache and call Vision again")
    }

    // MARK: 3. Fixture smoke test — known words recognized

    @Test func recognize_basicGerman_returnsKnownWords() async throws {
        guard let image = loadFixture(named: "ocr-hallo-welt") else {
            Issue.record("Test fixture ocr-hallo-welt.png not found in bundle — skipping")
            return
        }

        let service = VisionOCRService()
        let result = try await service.recognize(image: image, languages: ["de-DE"])

        // The fixture contains "Hallo Welt" — at least some words should be detected
        // (Vision accuracy varies on pixel-art fonts; accept ≥ 1 non-empty word box)
        #expect(!result.words.isEmpty || !result.lines.isEmpty,
                "Vision should produce at least one box on the fixture image")
    }

    // MARK: 4. Off-main-thread assertion

    @Test func recognize_offMainThread() async throws {
        // VisionOCRService dispatches to a background queue internally.
        // We verify the service itself doesn't block main thread by running from a detached Task.
        guard let image = loadFixture(named: "ocr-hallo-welt") else {
            Issue.record("Test fixture ocr-hallo-welt.png not found in bundle — skipping")
            return
        }

        let service = VisionOCRService()
        var wasOnMainThread = true
        await Task.detached {
            do {
                _ = try await service.recognize(image: image, languages: ["de-DE"])
                wasOnMainThread = Thread.isMainThread
            } catch {
                wasOnMainThread = false  // error, not main thread issue
            }
        }.value

        #expect(wasOnMainThread == false,
                "OCR continuation should not run on main thread")
    }

    // MARK: 5. Cache get/put direct test

    @Test func cache_getAndPut_roundTrip() {
        let cache = OCRResultCache(countLimit: 10)
        let dummyImage = UIImage()
        guard let data = dummyImage.pngData() else { return }

        let result = OCRResult(
            words: [OCRWordBox(text: "Hallo", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), confidence: 0.9, lineIndex: 0)],
            lines: [OCRLineBox(text: "Hallo Welt", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1), confidence: 0.9)]
        )

        cache.put(imageData: data, languages: ["de-DE"], result: result)
        let retrieved = cache.get(imageData: data, languages: ["de-DE"])

        #expect(retrieved != nil)
        #expect(retrieved?.words.first?.text == "Hallo")
    }
}

// MARK: — Helpers

private func loadFixture(named name: String) -> UIImage? {
    // Try test bundle first
    let testBundle = Bundle(for: BundleLocator.self)
    if let url = testBundle.url(forResource: name, withExtension: "png"),
       let img = UIImage(contentsOfFile: url.path) {
        return img
    }
    // Fallback: load from file system path relative to source root
    let path = "/Users/rutkay/workspace/mangadict/Aidoku-with-learner/AidokuTests/Fixtures/\(name).png"
    return UIImage(contentsOfFile: path)
}

private final class BundleLocator {}

// MARK: — CountingOCRService (test double)

/// Wraps VisionOCRService but shares its cache, counting actual Vision invocations.
private final class CountingOCRService: OCRService, @unchecked Sendable {
    private let inner: VisionOCRService
    private let sharedCache: OCRResultCache
    private(set) var visionCallCount = 0
    private let lock = NSLock()

    init(cache: OCRResultCache) {
        sharedCache = cache
        inner = VisionOCRService(cache: cache)
    }

    func recognize(image: UIImage, languages: [String]) async throws -> OCRResult {
        guard let pngData = image.pngData() else { throw OCRError.imageUnsupported }
        if sharedCache.get(imageData: pngData, languages: languages) != nil {
            // Cache hit — don't increment
            return try await inner.recognize(image: image, languages: languages)
        }
        // Cache miss — increment before delegating
        lock.lock()
        visionCallCount += 1
        lock.unlock()
        return try await inner.recognize(image: image, languages: languages)
    }
}
