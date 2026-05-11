//
//  BackupVocabularyEntry.swift
//  Aidoku
//
//  Codable backup struct for VocabularyEntry + its FamiliarityProgress.
//  Mirrors BackupHistory.swift pattern.
//
//  Dedup note: restore uses (language, lemma) as the composite key. If two
//  backups are merged and the same word exists in both, the one with the more
//  recent dateLastSeen wins (upsert keeps existing record and updates fields).
//

import CoreData

struct BackupVocabularyEntry: Codable, Hashable, Sendable {
    var id: UUID
    var lemma: String
    var surfaceForm: String
    var language: String
    var translation: String?
    var dateAdded: Date
    var dateLastSeen: Date
    var sourceMangaId: String?
    var sourceMangaSourceId: String?

    // Embedded familiarity (avoids a separate top-level array for the common case)
    var familiarityLevel: Int16
    var correctAnswers: Int32
    var lastReviewedAt: Date?
    var done: Bool

    init(object: VocabularyEntryObject) {
        // VocabularyEntry.id is modelled optional for CloudKit compatibility but is always
        // assigned in awakeFromInsert(); fall back to a fresh UUID defensively.
        id = object.id ?? UUID()
        lemma = object.lemma
        surfaceForm = object.surfaceForm
        language = object.language
        translation = object.translation
        dateAdded = object.dateAdded
        dateLastSeen = object.dateLastSeen
        sourceMangaId = object.sourceMangaId
        sourceMangaSourceId = object.sourceMangaSourceId
        familiarityLevel = object.progress?.level ?? 0
        correctAnswers = object.progress?.correctAnswers ?? 0
        lastReviewedAt = object.progress?.lastReviewedAt
        done = object.progress?.done ?? false
    }

    /// Restores or updates the CoreData object from this backup struct.
    /// Uses (language, lemma) as the composite key for upsert.
    @discardableResult
    func toObject(context: NSManagedObjectContext? = nil) -> VocabularyEntryObject {
        let ctx = context ?? CoreDataManager.shared.context
        // Upsert by natural key
        let existing = CoreDataManager.shared.getVocabularyEntry(language: language, lemma: lemma, context: ctx)
        let entry: VocabularyEntryObject
        if let existing {
            entry = existing
        } else {
            entry = VocabularyEntryObject(context: ctx)
            entry.id = id
            entry.dateAdded = dateAdded
        }
        entry.lemma = lemma
        entry.surfaceForm = surfaceForm
        entry.language = language
        entry.translation = translation
        entry.dateLastSeen = dateLastSeen
        entry.sourceMangaId = sourceMangaId
        entry.sourceMangaSourceId = sourceMangaSourceId

        // Upsert progress
        let progress = entry.progress ?? FamiliarityProgressObject(context: ctx)
        progress.level = familiarityLevel
        progress.correctAnswers = correctAnswers
        progress.lastReviewedAt = lastReviewedAt
        progress.done = done
        progress.entry = entry
        entry.progress = progress

        return entry
    }
}
