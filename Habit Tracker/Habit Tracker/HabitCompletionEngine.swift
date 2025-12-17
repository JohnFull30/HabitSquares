import Foundation
import CoreData
import EventKit

/// Calculates daily HabitCompletion rows from linked Reminders.
struct HabitCompletionEngine {

    // MARK: - Public API

    /// Recompute / upsert HabitCompletion rows for *today* based on the
    /// current Reminders state.
    static func upsertCompletionsForToday(
        in context: NSManagedObjectContext,
        reminders: [EKReminder]
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 1. Build a Set of reminder identifiers that are completed *today*
        let doneTodayIDs: Set<String> = Set(
            reminders.compactMap { reminder in
                guard reminder.isCompleted else { return nil }
                guard let completionDate = reminder.completionDate,
                      calendar.isDate(completionDate, inSameDayAs: today) else {
                    return nil
                }
                return reminder.calendarItemIdentifier
            }
        )

        print("✅ HabitCompletionEngine: doneTodayIDs = \(doneTodayIDs)")

        // 2. Fetch all habits
        let habitRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
        habitRequest.sortDescriptors = []

        let habits: [Habit]
        do {
            habits = try context.fetch(habitRequest)
        } catch {
            print("⚠️ HabitCompletionEngine: failed to fetch habits: \(error)")
            return
        }

        // 3. Fetch any existing completions for *today* and index them by habit
        let completionRequest: NSFetchRequest<HabitCompletion> = HabitCompletion.fetchRequest()
        completionRequest.predicate = NSPredicate(format: "date == %@", today as NSDate)
        completionRequest.sortDescriptors = []

        let existingCompletions: [HabitCompletion]
        do {
            existingCompletions = try context.fetch(completionRequest)
        } catch {
            print("⚠️ HabitCompletionEngine: failed to fetch existing completions: \(error)")
            return
        }

        var completionByHabit: [Habit: HabitCompletion] = [:]
        for completion in existingCompletions {
            if let habit = completion.habit {
                completionByHabit[habit] = completion
            }
        }

        // 4. For each habit, count required reminders and how many are done today
        for habit in habits {
            let habitName = habit.name ?? "<unnamed>"

            // 4a. Fetch links for this habit
            let linkRequest: NSFetchRequest<HabitReminderLink> = HabitReminderLink.fetchRequest()
            linkRequest.predicate = NSPredicate(format: "habit == %@", habit)

            let links: [HabitReminderLink]
            do {
                links = try context.fetch(linkRequest)
            } catch {
                print("⚠️ HabitCompletionEngine: failed to fetch links for habit \(habitName): \(error)")
                continue
            }

            if links.isEmpty {
                // No linked reminders ⇒ no required reminders, not complete
                let completion = completionByHabit[habit] ?? HabitCompletion(context: context)
                completion.habit = habit
                completion.date = today
                completion.isComplete = false

                print("📊 HabitCompletionEngine: habit '\(habitName)' has no links → not complete.")
                continue
            }

            // 4b. Decide which links are "required"
            // For now, treat every link as required.
            let requiredLinks = links
            let requiredCount = requiredLinks.count

            // 4c. Count how many required reminders are done today
            let completedRequired = requiredLinks.filter { link in
                guard let id = link.reminderIdentifier else { return false }
                return doneTodayIDs.contains(id)
            }.count

            let isComplete = requiredCount > 0 && completedRequired == requiredCount

            // 4d. Upsert the HabitCompletion row for (habit, today)
            let completion = completionByHabit[habit] ?? HabitCompletion(context: context)
            completion.habit = habit
            completion.date = today
            completion.isComplete = isComplete

            print("""
            📊 HabitCompletionEngine: habit '\(habitName)'
              required: \(requiredCount)
              done today: \(completedRequired)
              isComplete: \(isComplete)
            """)
        }

        // 5. Save
        do {
            try context.save()
            print("✅ HabitCompletionEngine: saved completions for today.")
        } catch {
            print("⚠️ HabitCompletionEngine: failed to save completions: \(error)")
        }
    }

    // MARK: - Debug helper

    /// Log the HabitCompletion rows for today so you can verify what the
    /// heatmap *should* be showing.
static func debugSummaries(in context: NSManagedObjectContext) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    let request: NSFetchRequest<HabitCompletion> = HabitCompletion.fetchRequest()
    request.predicate = NSPredicate(format: "date == %@", today as NSDate)
    request.sortDescriptors = []

    do {
        let results = try context.fetch(request)

        print("====== Habit completion summaries (debug) ======")
        for completion in results {
            let name = completion.habit?.name ?? "<unnamed>"
            let date = completion.date ?? today

            print("Habit: \(name)")
            print(" date: \(date)")
            print(" isComplete: \(completion.isComplete)")
        }
        print("====== end summaries ======")
    } catch {
        print("⚠️ HabitCompletionEngine: failed to fetch summaries: \(error)")
    }
}
}
