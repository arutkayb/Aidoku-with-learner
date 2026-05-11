//
//  FlashcardStateObject.swift
//  Aidoku
//
//  Hand-written NSManagedObject subclass for FlashcardState.
//  Ephemeral review state; NOT included in backups.
//  Cascade-deleted when its parent VocabularyEntry is deleted.
//

import Foundation
import CoreData

@objc(FlashcardStateObject)
public class FlashcardStateObject: NSManagedObject {
    /// CloudKit requires `id` to be optional in the model; assign a UUID at insertion time
    /// so callers can rely on it being non-nil for the lifetime of the row.
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil {
            id = UUID()
        }
    }
}

extension FlashcardStateObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FlashcardStateObject> {
        NSFetchRequest<FlashcardStateObject>(entityName: "FlashcardState")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var lastShownAt: Date?
    @NSManaged public var sessionCorrect: Int16

    @NSManaged public var entry: VocabularyEntryObject?
}
