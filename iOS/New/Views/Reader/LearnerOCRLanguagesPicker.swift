//
//  LearnerOCRLanguagesPicker.swift
//  Aidoku (iOS)
//
//  SwiftUI multi-select picker for OCR recognition languages.
//  Reads/writes JSON-encoded [String] under the UserDefaults key
//  "Learner.ocrLanguagesList". (Task 7)
//

import SwiftUI

/// Five-row toggle list bound to the JSON-encoded OCR language list.
/// At least one language must remain selected (the last toggle is disabled
/// when it would remove the only remaining language).
struct LearnerOCRLanguagesPicker: View {

    // Available language codes and their display names (must stay in sync with
    // coordinator's default and ReaderSettingsView's old select list).
    private static let languages: [(code: String, display: String)] = [
        ("de-DE", "German (de-DE)"),
        ("en-US", "English (en-US)"),
        ("ja-JP", "Japanese (ja-JP)"),
        ("fr-FR", "French (fr-FR)"),
        ("es-ES", "Spanish (es-ES)")
    ]

    private static let defaultsKey = "Learner.ocrLanguagesList"

    @State private var selected: Set<String>

    init() {
        let loaded = Self.loadFromDefaults()
        _selected = State(initialValue: loaded)
    }

    var body: some View {
        ForEach(Self.languages, id: \.code) { lang in
            let isOn = selected.contains(lang.code)
            let isLast = selected.count == 1 && isOn
            Toggle(lang.display, isOn: Binding(
                get: { selected.contains(lang.code) },
                set: { newValue in
                    if newValue {
                        selected.insert(lang.code)
                    } else if selected.count > 1 {
                        selected.remove(lang.code)
                    }
                    // Always persist after change
                    Self.saveToDefaults(selected)
                }
            ))
            .disabled(isLast)  // prevent deselecting the last language
        }
        // Keep UI in sync if another view changes the defaults (e.g. after migration)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let fresh = Self.loadFromDefaults()
            if fresh != selected { selected = fresh }
        }
    }

    // MARK: — Persistence helpers

    private static func loadFromDefaults() -> Set<String> {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let langs = try? JSONDecoder().decode([String].self, from: data), !langs.isEmpty {
            return Set(langs)
        }
        return ["de-DE"]
    }

    private static func saveToDefaults(_ langs: Set<String>) {
        guard !langs.isEmpty else { return }
        let sorted = langs.sorted()  // stable order for deterministic reads
        if let data = try? JSONEncoder().encode(sorted) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
