//
//  WidgetDataWriter.swift
//  Habit Tracker
//

import Foundation
import CoreData

enum WidgetDataWriter {

    /// Writes:
    /// 1) habits_index.json (for widget picker)
    /// 2) today_<habitID>.json per habit (today summary + days grid)
    /// 3) widget_snapshot.json fallback
    static func writeSnapshot(dayCount: Int = 60, in context: NSManagedObjectContext) {

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        let endExclusive = cal.date(byAdding: .day, value: 1, to: today) ?? today

        // yyyy-MM-dd key
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"

        func dayKey(_ d: Date) -> String { fmt.string(from: cal.startOfDay(for: d)) }
        let todayKey = dayKey(today)

        // Fetch habits
        let habitReq = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        let habits = (try? context.fetch(habitReq)) ?? []

        // Fetch completions in range [start, endExclusive)
        let compReq = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        compReq.predicate = NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, endExclusive as NSDate)
        let completions = (try? context.fetch(compReq)) ?? []

        // Map: habitID -> [dateKey: isComplete]
        var completeByHabitAndDay: [String: [String: Bool]] = [:]

        // Map: habitID -> today's completion object (for totals)
        var todayCompletionByHabitID: [String: NSManagedObject] = [:]

        for c in completions {
            guard
                let date = c.value(forKey: "date") as? Date,
                let habitObj = c.value(forKey: "habit") as? NSManagedObject
            else { continue }

            // ✅ IMPORTANT: use stable HabitID (same as WidgetCacheWriter + widget picker)
            let hid = HabitID.stableString(for: habitObj.objectID)

            let dk = dayKey(date)
            let isComplete = (c.value(forKey: "isComplete") as? Bool) ?? false

            completeByHabitAndDay[hid, default: [:]][dk] = isComplete

            if dk == todayKey {
                todayCompletionByHabitID[hid] = c
            }
        }

        // 1) Write habits index for picker
        let stubs: [WidgetHabitStub] = habits.map { h in
            let hid = HabitID.stableString(for: h.objectID)
            let name = (h.value(forKey: "name") as? String) ?? "Habit"
            return WidgetHabitStub(id: hid, name: name, colorHex: nil)
        }

        WidgetSharedStore.writeHabitsIndex(
            WidgetHabitsIndexPayload(updatedAt: Date(), habits: stubs)
        )

        // 2) Write per-habit payload
        for h in habits {
            let hid = HabitID.stableString(for: h.objectID)
            let habitName = (h.value(forKey: "name") as? String) ?? "Habit"

            let map = completeByHabitAndDay[hid] ?? [:]

            // Days: oldest -> newest, last is today
            let days: [WidgetDay] = (0..<dayCount).map { i in
                let d = cal.date(byAdding: .day, value: i - (dayCount - 1), to: today) ?? today
                let dk = dayKey(d)
                return WidgetDay(dateKey: dk, isComplete: map[dk] ?? false)
            }

            // Today totals from today's HabitCompletion (if any)
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

        // 3) Snapshot fallback (all habits complete on that day)
        let totalHabits = habits.count
        let overallDays: [WidgetDay] = (0..<dayCount).map { i in
            let d = cal.date(byAdding: .day, value: i - (dayCount - 1), to: today) ?? today
            let dk = dayKey(d)

            guard totalHabits > 0 else { return WidgetDay(dateKey: dk, isComplete: false) }

            let allDone = habits.allSatisfy { h in
                let hid = HabitID.stableString(for: h.objectID)
                return (completeByHabitAndDay[hid]?[dk] ?? false) == true
            }
            return WidgetDay(dateKey: dk, isComplete: allDone)
        }

        let completeHabitsToday = habits.filter { h in
            let hid = HabitID.stableString(for: h.objectID)
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

