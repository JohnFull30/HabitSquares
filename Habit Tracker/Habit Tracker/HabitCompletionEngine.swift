import Foundation
import CoreData
import EventKit

/// Calculates daily HabitCompletion rows from linked Reminders.
struct HabitCompletionEngine {

    // MARK: - Public API

    /// Recompute / upsert HabitCompletion rows for *today* based on the
    /// reminders that were fetched (your ReminderService decides which reminders are included).
    static func upsertCompletionsForToday(
        in context: NSManagedObjectContext,
        reminders: [EKReminder]
    ) {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        // IDs that exist in the reminders array we were given (i.e. “eligible” for today logic)
        let todayReminderIDs = Set(reminders.map { $0.calendarItemIdentifier })

        // ✅ Only count as "done today" if:
        // - reminder.isCompleted == true
        // - AND completionDate is within today’s window
        //
        // This prevents old completions (yesterday, etc.) from auto-counting today.
        func isCompletedToday(_ reminder: EKReminder) -> Bool {
            guard reminder.isCompleted else { return false }
            guard let completedAt = reminder.completionDate else { return false }
            return (startOfToday..<endOfToday).contains(completedAt)
        }

        let doneTodayIDs = Set(
            reminders
                .filter(isCompletedToday)
                .map { $0.calendarItemIdentifier }
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
        completionRequest.predicate = NSPredicate(format: "date == %@", startOfToday as NSDate)
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
                // No linked reminders ⇒ not complete
                let completion = completionByHabit[habit] ?? HabitCompletion(context: context)
                completion.habit = habit
                completion.date = startOfToday
                completion.isComplete = false

                print("📊 HabitCompletionEngine: habit '\(habitName)' has no links → not complete.")
                continue
            }

            // Prefer ekReminderID if present; fall back to reminderIdentifier (covers older data)
            func linkID(_ link: HabitReminderLink) -> String? {
                if let id = link.ekReminderID, !id.isEmpty { return id }
                if let id = link.reminderIdentifier, !id.isEmpty { return id }
                return nil
            }

            // Only count REQUIRED links that actually exist in the reminders we consider “today eligible”
            let requiredTodayLinks = links.filter { link in
                guard link.isRequired, let id = linkID(link) else { return false }
                return todayReminderIDs.contains(id)
            }

            let requiredCount = requiredTodayLinks.count

            let completedRequired = requiredTodayLinks.filter { link in
                guard let id = linkID(link) else { return false }
                return doneTodayIDs.contains(id)
            }.count

            let isComplete = requiredCount > 0 && completedRequired == requiredCount

            // 4d. Upsert the HabitCompletion row for (habit, today)
            let completion = completionByHabit[habit] ?? HabitCompletion(context: context)
            completion.habit = habit
            completion.date = startOfToday
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
