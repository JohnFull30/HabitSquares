//
//  WidgetCacheWriter.swift
//  Habit Tracker
//

import Foundation
import CoreData
import WidgetKit

enum WidgetCacheWriter {

    /// Writes:
    /// 1) habits_index.json (for the widget picker)
    /// 2) today_<habitID>.json per habit (today summary + days grid)
    static func writeTodayAndIndex(in context: NSManagedObjectContext,
                                   dayCount: Int = 60) {

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today

        // Date key formatter (must match the rest of your widget code)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"

        func dayKey(_ d: Date) -> String {
            fmt.string(from: cal.startOfDay(for: d))
        }

        // 1) Fetch habits
        let habitReq = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        let habits = (try? context.fetch(habitReq)) ?? []

        // 2) Fetch completions in range
        let compReq = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        compReq.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, today as NSDate)
        let completions = (try? context.fetch(compReq)) ?? []

        // Map: habitID -> [dateKey: isComplete]
        var completeByHabitAndDay: [String: [String: Bool]] = [:]

        // Map: habitID -> today's completion object (to grab totalRequired/completedRequired)
        var todayCompletionByHabitID: [String: NSManagedObject] = [:]
        let todayKey = dayKey(today)

        for c in completions {
            guard
                let date = c.value(forKey: "date") as? Date,
                let habitObj = c.value(forKey: "habit") as? NSManagedObject
            else { continue }

            let hid = HabitID.stableString(for: habitObj.objectID)
            let dk = dayKey(date)
            let isComplete = (c.value(forKey: "isComplete") as? Bool) ?? false

            completeByHabitAndDay[hid, default: [:]][dk] = isComplete

            if dk == todayKey {
                todayCompletionByHabitID[hid] = c
            }
        }

        // 3) Write habits index for picker
        let stubs: [WidgetHabitStub] = habits.compactMap { h in
            let hid = HabitID.stableString(for: h.objectID)
            let name = (h.value(forKey: "name") as? String) ?? "Habit"
            return WidgetHabitStub(id: hid, name: name, colorHex: nil)
        }

        WidgetSharedStore.writeHabitsIndex(
            WidgetHabitsIndexPayload(updatedAt: Date(), habits: stubs)
        )

        // 4) Write per-habit payload
        for h in habits {
            let hid = HabitID.stableString(for: h.objectID)
            let habitName = (h.value(forKey: "name") as? String) ?? "Habit"

            // Build days oldest -> newest
            let map = completeByHabitAndDay[hid] ?? [:]
            let days: [WidgetDay] = (0..<dayCount).map { i in
                let d = cal.date(byAdding: .day, value: i - (dayCount - 1), to: today) ?? today
                let dk = dayKey(d)
                return WidgetDay(dateKey: dk, isComplete: map[dk] ?? false)
            }

            // Today summary counts (from today's HabitCompletion, if available)
            let c = todayCompletionByHabitID[hid]
            let totalRequired = Int((c?.value(forKey: "totalRequired") as? Int32) ?? 0)
            let completedRequired = Int((c?.value(forKey: "completedRequired") as? Int32) ?? 0)
            let isComplete = map[todayKey] ?? false

            let payload = WidgetHabitTodayPayload(
                updatedAt: Date(),
                habitID: hid,
                habitName: habitName,
                totalRequired: totalRequired,
                completedRequired: completedRequired,
                isComplete: isComplete,
                days: days
            )

            WidgetSharedStore.writeToday(payload)
        }

        // Tell iOS to refresh widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }
}
