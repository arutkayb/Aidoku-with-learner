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

    /// Normalises a lemma for storage.
    /// Splits the input on any character that is not a letter, digit, apostrophe,
    /// or hyphen, then returns the longest resulting segment, lowercased and with
    /// leading/trailing apostrophes or hyphens trimmed. This preserves in-word
    /// hyphens ("auto-mobile") and apostrophes ("it's"), strips edge punctuation
    /// ("Tür,"→"tür", "foo."→"foo"), and discards stutter/ellipsis artifacts that
    /// would otherwise leave junk inside the lemma ("F..FURCHTBAR!"→"furchtbar").
    /// Returns an empty string if no usable segment exists.
    static func normalize(_ lemma: String) -> String {
        let inWord: Set<Unicode.Scalar> = ["'", "\u{2019}", "-"]
        var segments: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in lemma.unicodeScalars {
            let isWordChar = CharacterSet.letters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || inWord.contains(scalar)
            if isWordChar {
                current.append(scalar)
            } else if !current.isEmpty {
                segments.append(String(current))
                current.removeAll()
            }
        }
        if !current.isEmpty { segments.append(String(current)) }
        guard let longest = segments.max(by: { $0.unicodeScalars.count < $1.unicodeScalars.count }) else {
            return ""
        }
        let edgeChars = CharacterSet(charactersIn: "'\u{2019}-")
        return longest.trimmingCharacters(in: edgeChars).lowercased()
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
    @NSManaged public var notes: String?

    @NSManaged public var progress: FamiliarityProgressObject?
    @NSManaged public var flashcardState: FlashcardStateObject?
}
