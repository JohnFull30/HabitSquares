import Foundation
import CoreData
import EventKit
import WidgetKit

enum HabitCompletionEngine {
    static let liveSource = "reminders"
    static let historySource = "remindersHistory"

    static func syncTodayFromReminders(in context: NSManagedObjectContext,
                                       includeCompleted: Bool = true) {
        // A partial (incomplete-only) fetch must never clear a completed square.
        guard includeCompleted else { return }
        ReminderService.shared.requestAccessIfNeeded { ok in
            guard ok else { return }
            ReminderService.shared.fetchTodayReminders(includeCompleted: true) { reminders in
                Task { @MainActor in
                    do {
                        try updateToday(in: context, reminders: reminders)
                        WidgetRefresh.push(context)
                    } catch {
                        print("HabitCompletionEngine: today sync failed: \(error)")
                    }
                }
            }
        }
    }

    static func syncLast365DaysFromReminders(
        in context: NSManagedObjectContext,
        completion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        Task { @MainActor in
            let store = EKEventStore()
            guard await requestRemindersAccessIfNeeded(store: store) else {
                completion(false)
                return
            }
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let start = calendar.date(byAdding: .day, value: -364, to: today) ?? today
            let predicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: start, ending: today,
                calendars: store.calendars(for: .reminder))
            let fetched: [EKReminder]? = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
            }
            guard let reminders = fetched,
                  EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                completion(false)
                return
            }
            var keysByDay: [Date: Set<String>] = [:]
            for reminder in reminders where reminder.isCompleted {
                guard let date = reminder.completionDate else { continue }
                let day = calendar.startOfDay(for: date)
                guard day >= start, day < today else { continue }
                keysByDay[day, default: []].formUnion(ReminderLinkIdentity.keys(for: reminder))
            }
            do {
                try backfillHistory(in: context, doneKeysByDay: keysByDay, now: today)
                WidgetRefresh.push(context)
                completion(true)
            } catch {
                print("HabitCompletionEngine: history sync failed: \(error)")
                completion(false)
            }
        }
    }

    /// Only an observed, resolvable set of required reminders may update today's live row.
    /// Legacy/manual/seed rows have unknown provenance and are deliberately left intact.
    @MainActor
    static func updateToday(in context: NSManagedObjectContext,
                            reminders: [EKReminder], now: Date = Date()) throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let availableKeys = reminders.reduce(into: Set<String>()) {
            $0.formUnion(ReminderLinkIdentity.keys(for: $1))
        }
        let doneKeys = reminders.reduce(into: Set<String>()) { keys, reminder in
            guard reminder.isCompleted, let completed = reminder.completionDate,
                  completed >= today, completed < tomorrow else { return }
            keys.formUnion(ReminderLinkIdentity.keys(for: reminder))
        }
        for habit in try context.fetch(Habit.fetchRequest()) {
            let links = try requiredLinks(for: habit, in: context)
            guard !links.isEmpty,
                  links.allSatisfy({ !ReminderLinkIdentity.storedKeys($0).isDisjoint(with: availableKeys) }) else {
                // A missing/deleted/inaccessible reminder is not evidence of incompletion.
                continue
            }
            let existing = try completions(for: habit, day: today, in: context)
            // Preserve duplicates and all pre-existing rows of unknown/manual provenance.
            guard existing.count <= 1,
                  existing.first.map({ $0.source == liveSource }) ?? true else { continue }
            let row = existing.first ?? HabitCompletion(context: context)
            row.id = row.id ?? UUID()
            row.habit = habit
            row.date = today
            row.source = liveSource
            let done = links.filter { !ReminderLinkIdentity.storedKeys($0).isDisjoint(with: doneKeys) }.count
            row.totalRequired = Int16(clamping: links.count)
            row.completedRequired = Int16(clamping: done)
            row.isComplete = done == links.count
        }
        if context.hasChanges { try context.save() }
    }

    /// History is insert-only. Missing EventKit history must never erase stored history,
    /// and today's row belongs exclusively to the live sync, avoiding competing writers.
    @MainActor
    static func backfillHistory(in context: NSManagedObjectContext,
                                doneKeysByDay: [Date: Set<String>], now: Date = Date()) throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -364, to: today)!
        let habits = try context.fetch(Habit.fetchRequest())
        for habit in habits {
            let links = try requiredLinks(for: habit, in: context)
            guard !links.isEmpty else { continue }
            // Read the window once per habit, rather than issuing hundreds of day fetches
            // on the main context during startup. Retain all existing rows unchanged.
            let request = HabitCompletion.fetchRequest()
            request.predicate = NSPredicate(format: "habit == %@ AND date >= %@ AND date < %@",
                                            habit, firstDay as NSDate, today as NSDate)
            var existingDays = Set(try context.fetch(request).compactMap { row in
                row.date.map { calendar.startOfDay(for: $0) }
            })
            for (date, keys) in doneKeysByDay {
                let day = calendar.startOfDay(for: date)
                guard day >= firstDay, day < today, !existingDays.contains(day) else { continue }
                let done = links.filter { !ReminderLinkIdentity.storedKeys($0).isDisjoint(with: keys) }.count
                // Absence is ambiguous. Only import actual positive completion evidence.
                guard done > 0 else { continue }
                let row = HabitCompletion(context: context)
                row.id = UUID()
                row.habit = habit
                row.date = day
                row.source = historySource
                existingDays.insert(day)
                row.totalRequired = Int16(clamping: links.count)
                row.completedRequired = Int16(clamping: done)
                row.isComplete = done == links.count
            }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private static func requiredLinks(for habit: Habit,
                                      in context: NSManagedObjectContext) throws -> [HabitReminderLink] {
        let request = HabitReminderLink.fetchRequest()
        request.predicate = NSPredicate(format: "habit == %@ AND isRequired == YES", habit)
        return try context.fetch(request)
    }

    @MainActor
    private static func completions(for habit: Habit, day: Date,
                                    in context: NSManagedObjectContext) throws -> [HabitCompletion] {
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let request = HabitCompletion.fetchRequest()
        request.predicate = NSPredicate(format: "habit == %@ AND date >= %@ AND date < %@",
                                        habit, day as NSDate, nextDay as NSDate)
        return try context.fetch(request)
    }

    private static func requestRemindersAccessIfNeeded(store: EKEventStore) async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized: return true
        case .notDetermined:
            do { return try await store.requestFullAccessToReminders() }
            catch { return false }
        default: return false
        }
    }
}
