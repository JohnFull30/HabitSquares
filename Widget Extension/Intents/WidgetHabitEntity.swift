//
//  WidgetHabitEntity.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/25/25.
//


import AppIntents

struct WidgetHabitEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "Habit")
    static var defaultQuery = WidgetHabitEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}