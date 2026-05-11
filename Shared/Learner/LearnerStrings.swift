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
    /// Rule: lowercase + trim whitespace. Punctuation is preserved per Decision Register #6.
    public static func normalizeLemma(_ input: String) -> String {
        VocabularyEntryObject.normalize(input)
    }
}
