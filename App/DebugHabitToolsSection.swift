#if DEBUG

import SwiftUI
import CoreData
import WidgetKit

/// Debug-only tools related to a single Habit.
/// Keep these out of production screens by wrapping the caller in `#if DEBUG`.
struct DebugHabitToolsSection: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var habit: Habit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Seed 12 Days (Dev)") {
                HabitSeeder.seedCompletions(
                    dayCount: 12,
                    for: habit,
                    in: viewContext,
                    markComplete: true
                )
                refreshWidget()
            }

            Button("Reload Widget (Dev)") {
                refreshWidget()
            }
            .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func refreshWidget() {
        WidgetCacheWriter.writeTodayAndIndex(in: viewContext)
        WidgetCenter.shared.reloadAllTimelines()
        print("🧪 DebugHabitToolsSection: refreshed widget for habit \(habit.name ?? "Habit")")
    }
}

#endif
