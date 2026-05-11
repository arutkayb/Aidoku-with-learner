//
//  VocabularyManagerTests.swift
//  Aidoku
//
//  Swift Testing cases for CoreDataManager+Vocabulary and BackupVocabularyEntry.
//  Uses an in-memory NSPersistentContainer so tests don't touch the real store.
//

import Foundation
import CoreData
import Testing
@testable import Aidoku

// MARK: — Tests

@Suite struct VocabularyManagerTests {

    // MARK: Test 1 — create + fetch round-trip

    @Test func createAndFetch_roundTrip() throws {
        let container = makeInMemoryContainer()
        let ctx = container.viewContext

        // Create
        let entry = CoreDataManager.shared.upsertVocabularyEntry(
            language: "de-DE",
            lemma: "buch",
            surfaceForm: "Buch",
            translation: "book",
            sourceMangaId: "manga1",
            sourceMangaSourceId: "src1",
            context: ctx
        )

        // Fetch
        let fetched = CoreDataManager.shared.getVocabularyEntry(language: "de-DE", lemma: "buch", context: ctx)
        #expect(fetched != nil)
        #expect(fetched?.lemma == "buch")
        #expect(fetched?.surfaceForm == "Buch")
        #expect(fetched?.translation == "book")
        #expect(fetched?.language == "de-DE")
        #expect(fetched?.objectID == entry.objectID)
    }

    // MARK: Test 2 — familiarity caps at 3

    @Test func setFamiliarity_capsAtThree() throws {
        let container = makeInMemoryContainer()
        let ctx = container.viewContext

        let entry = CoreDataManager.shared.upsertVocabularyEntry(
            language: "de-DE", lemma: "wasser", surfaceForm: "Wasser",
            translation: "water", sourceMangaId: nil, sourceMangaSourceId: nil, context: ctx
        )
        // Call markFlashcardReview 4 times with correct=true
        for _ in 0..<4 {
            CoreDataManager.shared.markFlashcardReview(entry, correct: true, context: ctx)
        }
        let refetched = CoreDataManager.shared.getVocabularyEntry(language: "de-DE", lemma: "wasser", context: ctx)
        #expect(refetched?.progress?.level == 3) // level capped at 3
        #expect((refetched?.progress?.correctAnswers ?? 0) == 4) // correctAnswers always increments on correct, independent of level cap
    }

    // MARK: Test 3 — setDone locks level

    @Test func setDone_locksLevel() throws {
        let container = makeInMemoryContainer()
        let ctx = container.viewContext

        let entry = CoreDataManager.shared.upsertVocabularyEntry(
            language: "de-DE", lemma: "haus", surfaceForm: "Haus",
            translation: "house", sourceMangaId: nil, sourceMangaSourceId: nil, context: ctx
        )
        CoreDataManager.shared.setDone(entry, context: ctx)

        let fetched = CoreDataManager.shared.getVocabularyEntry(language: "de-DE", lemma: "haus", context: ctx)
        #expect(fetched?.progress?.done == true)
        #expect(fetched?.progress?.level == 3)

        // Subsequent review should NOT change level
        CoreDataManager.shared.markFlashcardReview(entry, correct: true, context: ctx)
        let refetched = CoreDataManager.shared.getVocabularyEntry(language: "de-DE", lemma: "haus", context: ctx)
        #expect(refetched?.progress?.level == 3)
    }

    // MARK: Test 4 — remove cascades progress

    @Test func removeEntry_cascadesProgress() throws {
        let container = makeInMemoryContainer()
        let ctx = container.viewContext

        let entry = CoreDataManager.shared.upsertVocabularyEntry(
            language: "de-DE", lemma: "katze", surfaceForm: "Katze",
            translation: "cat", sourceMangaId: nil, sourceMangaSourceId: nil, context: ctx
        )
        let progressId = entry.progress?.objectID

        CoreDataManager.shared.removeVocabularyEntry(entry, context: ctx)

        // Entry gone
        let fetched = CoreDataManager.shared.getVocabularyEntry(language: "de-DE", lemma: "katze", context: ctx)
        #expect(fetched == nil)

        // Progress gone (cascade delete from VocabularyEntry → progress)
        if let progressId {
            let progressFetch = try ctx.existingObject(with: progressId)
            #expect(progressFetch.isDeleted || progressFetch.managedObjectContext == nil)
        }
    }

    // MARK: Test 5 — backup round-trip

    @Test func backupRoundTrip_preservesEntries() throws {
        let container = makeInMemoryContainer()
        let ctx = container.viewContext

        // Create 3 entries with varying familiarity
        let words = [
            ("buch", "Buch", "book", Int16(0)),
            ("hund", "Hund", "dog", Int16(2)),
            ("katze", "Katze", "cat", Int16(1))
        ]
        for (lemma, surface, trans, level) in words {
            let entry = CoreDataManager.shared.upsertVocabularyEntry(
                language: "de-DE", lemma: lemma, surfaceForm: surface,
                translation: trans, sourceMangaId: nil, sourceMangaSourceId: nil, context: ctx
            )
            CoreDataManager.shared.setFamiliarity(entry, level: level, context: ctx)
        }

        // Serialize to backup
        let allEntries = CoreDataManager.shared.getAllVocabulary(language: "de-DE", context: ctx)
        #expect(allEntries.count == 3)
        let backupItems = allEntries.map { BackupVocabularyEntry(object: $0) }

        // Clear store
        for entry in allEntries {
            CoreDataManager.shared.removeVocabularyEntry(entry, context: ctx)
        }
        #expect(CoreDataManager.shared.getAllVocabulary(language: "de-DE", context: ctx).isEmpty)

        // Restore from backup
        for item in backupItems {
            _ = item.toObject(context: ctx)
        }
        try ctx.save()

        // Verify all 3 entries with correct familiarity
        let restored = CoreDataManager.shared.getAllVocabulary(language: "de-DE", context: ctx)
        #expect(restored.count == 3)
        let levelMap = Dictionary(uniqueKeysWithValues: restored.map { ($0.lemma, $0.progress?.level ?? -1) })
        #expect(levelMap["buch"] == 0)
        #expect(levelMap["hund"] == 2)
        #expect(levelMap["katze"] == 1)
    }

    // MARK: Test 6 — lemma normalization at insert time (Decision #6)

    @Test func upsert_normalizesLemma() throws {
        let container = makeInMemoryContainer()
        let ctx = container.viewContext

        // Insert with uppercase + surrounding whitespace; punctuation preserved per Decision #6.
        let entry = CoreDataManager.shared.upsertVocabularyEntry(
            language: "de-DE",
            lemma: "  Mädchen?  ",
            surfaceForm: "Mädchen?",
            translation: "girl",
            sourceMangaId: nil,
            sourceMangaSourceId: nil,
            context: ctx
        )
        // Whitespace trimmed and lowercased; '?' kept.
        #expect(entry.lemma == "mädchen?")

        // Fetch with a differently-cased / spaced lemma resolves to the same row.
        let same = CoreDataManager.shared.getVocabularyEntry(language: "de-DE", lemma: "MÄDCHEN?", context: ctx)
        #expect(same?.objectID == entry.objectID)

        // A lemma differing only in punctuation must NOT collide with the normalized one.
        let other = CoreDataManager.shared.getVocabularyEntry(language: "de-DE", lemma: "mädchen", context: ctx)
        #expect(other == nil)
    }
}

// MARK: — In-memory container factory

private func makeInMemoryContainer() -> NSPersistentContainer {
    let bundle = Bundle(for: CoreDataManager.self)
    guard let modelURL = bundle.url(forResource: "Aidoku", withExtension: "momd") else {
        // Fall back to direct model URL lookup
        let container = NSPersistentContainer(name: "Aidoku")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { fatalError("In-memory store error: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }
    guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
        fatalError("Cannot load model from \(modelURL)")
    }
    let container = NSPersistentContainer(name: "Aidoku", managedObjectModel: model)
    let description = NSPersistentStoreDescription()
    description.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [description]
    container.loadPersistentStores { _, error in
        if let error { fatalError("In-memory store error: \(error)") }
    }
    container.viewContext.automaticallyMergesChangesFromParent = true
    return container
}
