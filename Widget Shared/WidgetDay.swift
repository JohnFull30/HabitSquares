import Foundation

// MARK: - Core models shared with widget/app

struct WidgetDay: Codable, Hashable {
    /// "yyyy-MM-dd" in the user's current timezone
    var dateKey: String
    var isComplete: Bool
}

struct WidgetSnapshot: Codable {
    var updatedAt: Date
    /// Oldest → newest
    var days: [WidgetDay]
    var totalHabits: Int
    var completeHabits: Int
}

// MARK: - Placeholder (ONLY for WidgetKit placeholder/snapshot UI)

enum WidgetSnapshotStore {

    static func placeholder(dayCount: Int = 60) -> WidgetSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today

        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"

        let days = (0..<dayCount).map { i -> WidgetDay in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            return WidgetDay(dateKey: fmt.string(from: d), isComplete: false)
        }

        return WidgetSnapshot(
            updatedAt: Date(),
            days: days,
            totalHabits: 0,
            completeHabits: 0
        )
    }
}
