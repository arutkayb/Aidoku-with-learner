//
//  LearnerStrings.swift
//  Aidoku
//
//  Shared string-normalization helper used across Learner tasks (6, 7, 8).
//

import Foundation

public enum LearnerStrings {
    /// Normalizes a surface form into a lookup lemma.
    /// Rule: lowercase + trim whitespace + trim leading/trailing punctuation.
    /// Matches the normalization applied by VocabularyEntryObject.normalize at storage time.
    public static func normalizeLemma(_ input: String) -> String {
        input
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
