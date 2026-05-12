//
//  ContentView.swift
//  OCRSpike
//
//  Image picker + OCR runner + overlay rendering.
//  Loads bundled images from TestImages/, runs OCR, displays bounding-box overlay.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var images: [String] = []

    var body: some View {
        NavigationStack {
            Group {
                if images.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No test images found.")
                            .font(.headline)
                        Text("Drop PNG files into\nOCRSpike/TestImages/\nand rebuild.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List(images, id: \.self) { name in
                        NavigationLink(name) {
                            OCRDetailView(imageName: name)
                        }
                    }
                }
            }
            .navigationTitle("OCR Spike")
        }
        .onAppear {
            images = loadBundledImageNames()
        }
    }

    private func loadBundledImageNames() -> [String] {
        // Images are bundled as resources from OCRSpike/TestImages/
        // They appear in the main bundle at the top level (folder reference adds them flat).
        let extensions = ["png", "jpg", "jpeg"]
        guard let resourcePath = Bundle.main.resourcePath else { return [] }
        let fm = FileManager.default
        let all = (try? fm.contentsOfDirectory(atPath: resourcePath)) ?? []
        return all
            .filter { name in extensions.contains(where: { name.hasSuffix(".\($0)") }) }
            .sorted()
    }
}

// MARK: - OCR Detail View

struct OCRDetailView: View {
    let imageName: String

    @State private var wordBoxes: [WordBox] = []
    @State private var lineBoxes: [LineBox] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showWordLevel = true
    @State private var lastTapped: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toggle
            Picker("Box Level", selection: $showWordLevel) {
                Text("Word").tag(true)
                Text("Line").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let err = errorMessage {
                Text("Error: \(err)")
                    .foregroundStyle(.red)
                    .padding()
            }
            if let msg = lastTapped {
                Text("Tapped: \"\(msg)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            // Image + overlay
            ScrollView([.horizontal, .vertical]) {
                if let uiImage = loadImage() {
                    ImageOverlayView(
                        image: uiImage,
                        wordBoxes: wordBoxes,
                        lineBoxes: lineBoxes,
                        showWordLevel: showWordLevel,
                        onTap: { text in
                            lastTapped = text
                            print("wordTapped: \(text)")
                        }
                    )
                } else {
                    Text("Could not load image: \(imageName)")
                        .padding()
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Running OCR…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .navigationTitle(imageName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await runOCR()
        }
        .onChange(of: showWordLevel) { _, _ in
            // Level switch is immediate from cached results — no re-OCR needed.
        }
    }

    private func loadImage() -> UIImage? {
        UIImage(named: imageName) ?? UIImage(contentsOfFile:
            Bundle.main.path(forResource: imageName.components(separatedBy: ".").first,
                             ofType: imageName.components(separatedBy: ".").last) ?? ""
        )
    }

    private func runOCR() async {
        guard let image = loadImage() else {
            errorMessage = "Image not found in bundle"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let (words, lines) = try await OCRRunner().recognizeWords(in: image)
            wordBoxes = words
            lineBoxes = lines
            print("OCR done — \(words.count) word boxes, \(lines.count) line boxes")
            if words.isEmpty {
                print("WARNING: 0 word boxes. OCR pipeline may be broken or image has no recognizable text.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Image + Overlay

struct ImageOverlayView: View {
    let image: UIImage
    let wordBoxes: [WordBox]
    let lineBoxes: [LineBox]
    let showWordLevel: Bool
    let onTap: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = fittedSize(imageSize: image.size, containerSize: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                // Overlay word/line boxes
                let boxes: [(text: String, rect: CGRect)] = showWordLevel
                    ? wordBoxes.map { ($0.text, $0.rect) }
                    : lineBoxes.map { ($0.text, $0.rect) }

                ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                    let viewRect = visionRectToViewRect(box.rect, imageSize: size)
                    Button {
                        onTap(box.text)
                    } label: {
                        Rectangle()
                            .fill(Color.yellow.opacity(0.3))
                            .border(Color.yellow.opacity(0.8), width: 1)
                    }
                    .accessibilityLabel(box.text)
                    .frame(width: viewRect.width, height: viewRect.height)
                    .offset(x: viewRect.minX, y: viewRect.minY)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
    }

    /// Converts a Vision normalized bounding rect (bottom-left origin) to SwiftUI view coords (top-left origin).
    private func visionRectToViewRect(_ visionRect: CGRect, imageSize: CGSize) -> CGRect {
        let x = visionRect.origin.x * imageSize.width
        // Vision: y=0 is bottom; SwiftUI: y=0 is top. Flip Y.
        let y = (1.0 - visionRect.origin.y - visionRect.height) * imageSize.height
        let w = visionRect.width * imageSize.width
        let h = visionRect.height * imageSize.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func fittedSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let scale2 = max(scale, 1.0) // don't upscale below natural size
        return CGSize(width: imageSize.width * scale2, height: imageSize.height * scale2)
    }
}
