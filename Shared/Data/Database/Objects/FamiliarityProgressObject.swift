//
//  FamiliarityProgressObject.swift
//  Aidoku
//
//  Hand-written NSManagedObject subclass for FamiliarityProgress.
//  One-to-one with VocabularyEntryObject.
//

import Foundation
import CoreData

@objc(FamiliarityProgressObject)
public class FamiliarityProgressObject: NSManagedObject {

    /// Convenience: level capped at 3.
    var clampedLevel: Int16 { min(level, 3) }
}

extension FamiliarityProgressObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FamiliarityProgressObject> {
        NSFetchRequest<FamiliarityProgressObject>(entityName: "FamiliarityProgress")
    }

    @NSManaged public var level: Int16
    @NSManaged public var correctAnswers: Int32
    @NSManaged public var lastReviewedAt: Date?
    @NSManaged public var done: Bool

    @NSManaged public var entry: VocabularyEntryObject?
}
