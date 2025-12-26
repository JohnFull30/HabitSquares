//
//  HabitID.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/23/25.
//


import Foundation
import CoreData

enum HabitID {
    /// Works well for MVP: stable for a given Core Data store.
    /// (Later, if you add an explicit UUID attribute on Habit, swap to that.)
    static func stableString(for habitObjectID: NSManagedObjectID) -> String {
        habitObjectID.uriRepresentation().absoluteString
    }
}