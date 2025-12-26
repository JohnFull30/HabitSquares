//
//  WidgetDataWriter.swift
//  Habit Tracker
//

import Foundation
import CoreData

enum WidgetDataWriter {

    /// Writes:
    /// - habits_index.json (for the widget picker)
    /// - today_<habitID>.json (per habit, includes heatmap days + today counts)
    /// - widget_snapshot.json (overall cache, optional fallback)
    static func writeSnapshot(dayCount: Int = 60, in context: NSManagedObjectContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today

        // Date key formatter
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"

        func dayKey(_ d: Date) -> String {
            fmt.string(from: cal.startOfDay(for: d))
        }

        // Fetch all habits
        let habitReq = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        let habits = (try? context.fetch(habitReq)) ?? []
        let totalHabits = habits.count

        // Fetch completions in range
        let completionReq = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        completionReq.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, today as NSDate)
        let completions = (try? context.fetch(completionReq)) ?? []

        // Map: habitID -> (dateKey -> isComplete)
        var completeByHabitAndDay: [String: [String: Bool]] = [:]

        // Map: habitID -> today's counts
        struct TodayCounts {
            var totalRequired: Int = 0
            var completedRequired: Int = 0
            var isComplete: Bool = false
        }
        var todayByHabit: [String: TodayCounts] = [:]

        let todayKey = dayKey(today)

        for c in completions {
            guard
                let d = c.value(forKey: "date") as? Date,
                let habitObj = c.value(forKey: "habit") as? NSManagedObject
            else { continue }

            let habitID = habitObj.objectID.uriRepresentation().absoluteString
            let dk = dayKey(d)
            let isDone = (c.value(forKey: "isComplete") as? Bool) ?? false

            completeByHabitAndDay[habitID, default: [:]][dk] = isDone

            // Capture today's totals for this habit (if this completion is for today)
            if dk == todayKey {
                let totalReq = (c.value(forKey: "totalRequired") as? Int) ?? 0
                let doneReq  = (c.value(forKey: "completedRequired") as? Int) ?? 0
                todayByHabit[habitID] = TodayCounts(
                    totalRequired: totalReq,
                    completedRequired: doneReq,
                    isComplete: isDone
                )
            }
        }

        // Build days array (oldest -> newest) once
        let dayKeys: [String] = (0..<dayCount).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            return dayKey(d)
        }

        // 1) Write habits index (picker)
        let stubs: [WidgetHabitStub] = habits.map { h in
            let id = h.objectID.uriRepresentation().absoluteString
            let name = (h.value(forKey: "name") as? String) ?? "Habit"
            // If you later store color on Habit, map it here
            return WidgetHabitStub(id: id, name: name, colorHex: nil)
        }

        WidgetSharedStore.writeHabitsIndex(
            WidgetHabitsIndexPayload(updatedAt: Date(), habits: stubs)
        )

        // 2) Write per-habit payloads (this is what the widget will use for selected habit)
        for h in habits {
            let habitID = h.objectID.uriRepresentation().absoluteString
            let habitName = (h.value(forKey: "name") as? String) ?? "Habit"

            let map = completeByHabitAndDay[habitID] ?? [:]
            let days: [WidgetDay] = dayKeys.map { dk in
                WidgetDay(dateKey: dk, isComplete: map[dk] ?? false)
            }

            let tc = todayByHabit[habitID] ?? TodayCounts()

            let payload = WidgetHabitTodayPayload(
                updatedAt: Date(),
                habitID: habitID,
                habitName: habitName,
                totalRequired: tc.totalRequired,
                completedRequired: tc.completedRequired,
                isComplete: tc.isComplete,
                days: days
            )

            WidgetSharedStore.writeToday(payload)
        }

        // 3) Optional: Write an overall snapshot fallback (all habits complete that day)
        let overallDays: [WidgetDay] = dayKeys.map { dk in
            guard totalHabits > 0 else { return WidgetDay(dateKey: dk, isComplete: false) }
            let allDone = habits.allSatisfy { h in
                let hid = h.objectID.uriRepresentation().absoluteString
                return (completeByHabitAndDay[hid]?[dk] ?? false) == true
            }
            return WidgetDay(dateKey: dk, isComplete: allDone)
        }

        let completeHabitsToday = habits.filter { h in
            let hid = h.objectID.uriRepresentation().absoluteString
            return (completeByHabitAndDay[hid]?[todayKey] ?? false) == true
        }.count

        let snapshot = WidgetSnapshot(
            updatedAt: Date(),
            days: overallDays,
            totalHabits: totalHabits,
            completeHabits: completeHabitsToday
        )

        WidgetSharedStore.writeSnapshot(snapshot)
    }
}
