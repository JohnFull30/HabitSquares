//
//  WidgetHabitEntityQuery.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/25/25.
//


import AppIntents

struct WidgetHabitEntityQuery: EntityQuery {

    func suggestedEntities() async throws -> [WidgetHabitEntity] {
        let stubs = WidgetSharedStore.readHabitsIndex()?.habits ?? []
        return stubs
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { WidgetHabitEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [WidgetHabitEntity.ID]) async throws -> [WidgetHabitEntity] {
        let all = try await suggestedEntities()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }

    func defaultResult() async -> WidgetHabitEntity? {
        try? await suggestedEntities().first
    }
}