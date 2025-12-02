import Foundation

/// A single habit owned by HabitSquares.
/// For now this is an in-memory model (no Core Data yet).
struct HabitModel: Identifiable {
    let id: UUID
    var name: String
    var colorHex: String
    var trackingMode: String
    var days: [HabitDay]
}

/// Represents a single calendar day for a habit.
struct HabitDay: Identifiable {
    let id = UUID()
    let date: Date
    var isComplete: Bool
}

/// Simple demo factory so we have fake data for the UI.
struct HabitDemoData {
    /// Generates a single habit with the last 30 days of fake completions.
    static func makeSampleHabit() -> HabitModel {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Generate last 30 days
        let days = (0..<30).compactMap { offset -> HabitDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            // Fake pattern: complete ~50% of days
            let isComplete = Bool.random()
            return HabitDay(date: date, isComplete: isComplete)
        }
        .sorted { $0.date < $1.date } // oldest → newest

        return HabitModel(
            id: UUID(),
            name: "Move for 30 minutes",
            colorHex: "#22C55E",
            trackingMode: "manual",
            days: days
        )
    }
    /// Generates several habits, each with its own fake 30-day history.
    static func makeSampleHabits() -> [HabitModel] {
        let namesAndColors: [(String, String)] = [
            ("Move for 30 minutes", "#22C55E"), // green
            ("Read 10 pages", "#3B82F6"),       // blue
            ("Meditate 5 minutes", "#F97316")   // orange
        ]

        return namesAndColors.map { name, color in
            // Reuse the existing single-habit generator, but override name/color.
            var habit = makeSampleHabit()
            habit.name = name
            habit.colorHex = color
            return habit
        }
    }
}
