import Foundation

struct WidgetDay: Codable, Hashable {
    /// "yyyy-MM-dd"
    var dateKey: String
    var isComplete: Bool
}

struct WidgetSnapshot: Codable {
    var updatedAt: Date
    /// Oldest → newest (we’ll store up to 60)
    var days: [WidgetDay]
    var totalHabits: Int
    var completeHabits: Int
    
}


enum WidgetSnapshotStore {
    static let filename = "widget_snapshot.json"

    // ✅ MUST match Xcode Signing & Capabilities App Group exactly
    static let appGroupID = "group.pullerlabs.habitsquares"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url)
        else { return nil }

        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("✗ WidgetSnapshotStore.save failed:", error)
        }
    }

    static func placeholder(dayCount: Int = 60) -> WidgetSnapshot {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"

        let days = (0..<dayCount).map { i -> WidgetDay in
            let d = cal.date(byAdding: .day, value: -(dayCount - 1 - i), to: today)!
            return WidgetDay(dateKey: fmt.string(from: d), isComplete: (i % 4 != 0))
        }

        return WidgetSnapshot(updatedAt: Date(), days: days, totalHabits: 4, completeHabits: 3)
    }
}
