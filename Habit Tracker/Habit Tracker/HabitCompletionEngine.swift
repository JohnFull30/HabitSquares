import Foundation
import CoreData
import EventKit

/// Turns today's Reminders state into HabitCompletion rows.
struct HabitCompletionEngine {

    // MARK: - Public API

    /// Recompute and save today's HabitCompletion rows based on today's reminders.
    ///
    /// - Parameters:
    ///   - reminders: EKReminders for *today* (includeCompleted = true).
    ///   - context:   Core Data viewContext.
    static func updateCompletionsForToday(from reminders: [EKReminder],
                                          in context: NSManagedObjectContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Map reminders by identifier for quick lookup
        var remindersById: [String: EKReminder] = [:]
        for reminder in reminders {
            remindersById[reminder.calendarItemIdentifier] = reminder
        }

        // Fetch all habits
        let habitRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
        habitRequest.sortDescriptors = []
        let habits: [Habit]
        do {
            habits = try context.fetch(habitRequest)
        } catch {
            print("❌ HabitCompletionEngine: failed to fetch habits: \(error)")
            return
        }

        // Fetch all links for these habits
        let linkRequest: NSFetchRequest<HabitReminderLink> = HabitReminderLink.fetchRequest()
        linkRequest.predicate = NSPredicate(format: "habit IN %@", habits)
        let links: [HabitReminderLink]
        do {
            links = try context.fetch(linkRequest)
        } catch {
            print("❌ HabitCompletionEngine: failed to fetch links: \(error)")
            return
        }

        print("🧮 HabitCompletionEngine: computing for \(habits.count) habits, \(links.count) links")

        for habit in habits {
            // Only required links drive completion
            let habitLinks = links.filter { $0.habit == habit && $0.isRequired }

            var totalRequired = 0
            var completedToday = 0

            for link in habitLinks {
                guard let identifier = link.reminderIdentifier,
                      let reminder   = remindersById[identifier] else {
                    continue
                }

                totalRequired += 1

                var doneToday = false
                if reminder.isCompleted, let completionDate = reminder.completionDate {
                    doneToday = calendar.isDate(completionDate, inSameDayAs: today)
                }

                if doneToday { completedToday += 1 }

                print(
                    "   🔗 HabitCompletionEngine: habit '\(habit.name ?? "Habit")' " +
                    "reminder '\(reminder.title ?? "Untitled")' " +
                    "isCompleted=\(reminder.isCompleted) " +
                    "completionDate=\(String(describing: reminder.completionDate)) " +
                    "doneToday=\(doneToday)"
                )
            }

            let isComplete: Bool
            if totalRequired == 0 {
                // No required reminders → we can't mark complete based on Reminders
                isComplete = false
            } else {
                isComplete = (completedToday == totalRequired)
            }

            let completion = fetchOrCreateCompletion(for: habit, on: today, in: context)
            completion.date = today          // `Date`, not `NSDate`
            completion.isComplete = isComplete
        }

        do {
            try context.save()
            debugSummaries(in: context, on: today)
            print("✅ HabitCompletionEngine: saved completions for today.")
        } catch {
            print("❌ HabitCompletionEngine: failed to save completions: \(error)")
        }
    }

    // MARK: - Debug helper used by ContentView

    /// Matches the old `debugSummaries` name that ContentView calls.
    static func debugSummaries(in context: NSManagedObjectContext,
                               on day: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: day)

        let request: NSFetchRequest<HabitCompletion> = HabitCompletion.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@", today as NSDate)

        guard let results = try? context.fetch(request) else {
            print("⚠️ HabitCompletionEngine: failed to fetch summaries for logging.")
            return
        }

        print("====== Habit completion summaries (debug) ======")
        for completion in results {
            let name = completion.habit?.name ?? "Habit"
            print("Habit: \(name)")
            print("  isComplete: \(completion.isComplete)")
        }
        print("====== end summaries ======")
    }

    // MARK: - Private helpers

    /// Fetch (or create) the HabitCompletion for a given habit + day.
    private static func fetchOrCreateCompletion(for habit: Habit,
                                                on day: Date,
                                                in context: NSManagedObjectContext) -> HabitCompletion {
        let request: NSFetchRequest<HabitCompletion> = HabitCompletion.fetchRequest()
        request.predicate = NSPredicate(format: "habit == %@ AND date == %@", habit, day as NSDate)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            return existing
        }

        let newCompletion = HabitCompletion(context: context)
        newCompletion.habit = habit
        newCompletion.date = day
        newCompletion.isComplete = false
        return newCompletion
    }
}
