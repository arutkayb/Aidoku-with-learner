//
//  VocabularyEntryObject.swift
//  Aidoku
//
//  Hand-written NSManagedObject subclass for VocabularyEntry.
//  Auto-generated CoreData properties (+CoreDataProperties) are produced by Xcode at build time.
//

import Foundation
import CoreData

@objc(VocabularyEntryObject)
public class VocabularyEntryObject: NSManagedObject {

    /// CloudKit requires `id` to be optional in the model; we assign a UUID at insertion time
    /// so callers can rely on it being non-nil for the lifetime of the row.
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil {
            id = UUID()
        }
    }

    /// Composite identifier for use as a dictionary key or Hashable identity.
    struct Identifier: Hashable {
        let language: String
        let lemma: String
    }

    var identifier: Identifier {
        Identifier(language: language, lemma: lemma)
    }

    /// Normalises a lemma for storage (lowercase + whitespace-trim only).
    /// Per Decision Register #6: punctuation is preserved.
    static func normalize(_ lemma: String) -> String {
        lemma.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Upserts fields from caller-supplied values. Does NOT save the context.
    func load(
        language: String,
        lemma: String,
        surfaceForm: String,
        translation: String?,
        sourceMangaId: String?,
        sourceMangaSourceId: String?
    ) {
        self.language = language
        self.lemma = lemma
        self.surfaceForm = surfaceForm
        self.translation = translation
        self.sourceMangaId = sourceMangaId
        self.sourceMangaSourceId = sourceMangaSourceId
        self.dateLastSeen = Date()
    }
}

extension VocabularyEntryObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<VocabularyEntryObject> {
        NSFetchRequest<VocabularyEntryObject>(entityName: "VocabularyEntry")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var lemma: String
    @NSManaged public var surfaceForm: String
    @NSManaged public var language: String
    @NSManaged public var translation: String?
    @NSManaged public var dateAdded: Date
    @NSManaged public var dateLastSeen: Date
    @NSManaged public var sourceMangaId: String?
    @NSManaged public var sourceMangaSourceId: String?

    @NSManaged public var progress: FamiliarityProgressObject?
    @NSManaged public var flashcardState: FlashcardStateObject?
}
