import Foundation
import CoreData

enum WidgetDataWriter {

    /// Writes a 60-day snapshot. Widget will display 30 (small) or 60 (medium).
    static func writeSnapshot(dayCount: Int = 60, in context: NSManagedObjectContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(dayCount - 1), to: today)!

        // Fetch all habits
        let habitReq = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        let habits = (try? context.fetch(habitReq)) ?? []
        let totalHabits = habits.count

        // Fetch completions in range
        let completionReq = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        completionReq.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, today as NSDate)
        let completions = (try? context.fetch(completionReq)) ?? []

        // Date key formatter
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"

        func dayKey(_ d: Date) -> String { fmt.string(from: cal.startOfDay(for: d)) }

        // Map: habitURI|dateKey -> isComplete
        var completionMap: [String: Bool] = [:]
        for c in completions {
            guard
                let d = c.value(forKey: "date") as? Date,
                let habitObj = c.value(forKey: "habit") as? NSManagedObject
            else { continue }

            let isComplete = (c.value(forKey: "isComplete") as? Bool) ?? false
            let key = habitObj.objectID.uriRepresentation().absoluteString + "|" + dayKey(d)
            completionMap[key] = isComplete
        }

        // Build days oldest -> newest
        let days: [WidgetDay] = (0..<dayCount).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let dk = dayKey(d)

            guard totalHabits > 0 else {
                return WidgetDay(dateKey: dk, isComplete: false)
            }

            let allDone = habits.allSatisfy { h in
                let k = h.objectID.uriRepresentation().absoluteString + "|" + dk
                return completionMap[k] == true
            }

            return WidgetDay(dateKey: dk, isComplete: allDone)
        }

        // Today summary
        let completeHabits = habits.filter { h in
            let k = h.objectID.uriRepresentation().absoluteString + "|" + dayKey(today)
            return completionMap[k] == true
        }.count

        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            days: days,
            totalHabits: totalHabits,
            completeHabits: completeHabits
        )

        WidgetSnapshotStore.save(snapshot)
    }
}
