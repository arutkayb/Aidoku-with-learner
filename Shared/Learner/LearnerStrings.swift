//
//  LearnerStrings.swift
//  Aidoku
//
//  Shared string-normalization helper used across Learner tasks (6, 7, 8).
//

import Foundation

public enum LearnerStrings {
    /// Normalizes a surface form into a lookup lemma.
    /// Delegates to `VocabularyEntryObject.normalize` so the badge-lookup key on the
    /// overlay (which uses the entity-level normalizer directly) cannot diverge from
    /// the lookup key produced when a word is added to vocab.
    /// Rule: lowercase + trim whitespace. Edge punctuation and symbols are stripped;
    /// in-word punctuation (hyphen, apostrophe) is preserved. See Task 4 plan.
    public static func normalizeLemma(_ input: String) -> String {
        VocabularyEntryObject.normalize(input)
    }
}

// MARK: — Learner Gate (Task 1)

/// Per-manga gate mode stored under `Learner.mode.{mangaId}`.
/// Default (key absent) = `.inherit`.
public enum LearnerGateMode: String {
    case inherit = "inherit"
    case on = "on"
    case off = "off"
}

/// Helpers for evaluating whether Learner is active for a given manga.
public enum LearnerGate {

    // MARK: — Public interface

    /// Returns true if Learner should be active for `mangaId`, considering both
    /// the per-manga mode and the global toggle.
    public static func isEnabled(mangaId: String) -> Bool {
        let global = UserDefaults.standard.bool(forKey: "Learner.globallyEnabled")
        switch mode(for: mangaId) {
        case .on:      return true
        case .off:     return false
        case .inherit: return global
        }
    }

    /// Returns the current `LearnerGateMode` for `mangaId`.
    /// Performs a one-time migration from the old Bool key if present.
    public static func mode(for mangaId: String) -> LearnerGateMode {
        migrateLegacyBoolKeyIfNeeded(mangaId)
        let raw = UserDefaults.standard.string(forKey: modeKey(for: mangaId)) ?? "inherit"
        return LearnerGateMode(rawValue: raw) ?? .inherit
    }

    /// The UserDefaults key for per-manga mode.
    public static func modeKey(for mangaId: String) -> String {
        "Learner.mode.\(mangaId)"
    }

    /// The old boolean UserDefaults key (pre-Task 1).
    public static func legacyBoolKey(for mangaId: String) -> String {
        "Learner.enabled.\(mangaId)"
    }

    // MARK: — Migration

    /// One-shot migration from old `Learner.enabled.{mangaId}` Bool to new String key.
    /// - `true`  → writes `"on"` to the new key, removes old key.
    /// - `false` → removes old key only (absence == inherit; the user's intent when
    ///             they previously had it false was "don't enable" = off, but since the
    ///             old UI was a binary toggle there's no way to distinguish "explicitly
    ///             off" from "never set". Mapping absent → inherit is safer UX).
    /// Idempotent: if the new key already exists, the old key is simply removed.
    public static func migrateLegacyBoolKeyIfNeeded(_ mangaId: String) {
        let legacyKey = legacyBoolKey(for: mangaId)
        let newKey = modeKey(for: mangaId)
        // Only migrate if the old key is present (has ever been set)
        guard UserDefaults.standard.object(forKey: legacyKey) != nil else { return }
        // Only write new key if not already set (avoid overwriting an intentional choice)
        if UserDefaults.standard.object(forKey: newKey) == nil {
            let wasOn = UserDefaults.standard.bool(forKey: legacyKey)
            if wasOn {
                UserDefaults.standard.set("on", forKey: newKey)
            }
            // false → don't write new key; absence = inherit
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}
