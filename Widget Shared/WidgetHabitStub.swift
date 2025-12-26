//
//  WidgetHabitStub.swift
//  Habit Tracker
//

import Foundation

/// A lightweight habit model the widget can use in its picker.
/// Keep this stable + small.
struct WidgetHabitStub: Codable, Hashable, Identifiable {
    var id: String         // stable string id (HabitID.stableString)
    var name: String
    var colorHex: String?  // optional (keep for future)
}

/// Stored once so the widget can query available habits for the picker.
struct WidgetHabitsIndexPayload: Codable {
    var updatedAt: Date
    var habits: [WidgetHabitStub]
}

/// Stored per-habit so the widget can render *that habit's* grid + today summary quickly.
struct WidgetHabitTodayPayload: Codable {
    var updatedAt: Date
    var habitID: String
    var habitName: String

    // Today summary (for optional UI later)
    var totalRequired: Int
    var completedRequired: Int
    var isComplete: Bool

    // Heatmap days (oldest -> newest)
    var days: [WidgetDay]
}
