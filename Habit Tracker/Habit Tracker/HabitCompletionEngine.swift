import CoreData
import EventKit

struct HabitCompletionEngine {

    struct Summary {
        let requiredCount: Int
        let completedRequiredCount: Int
        var isComplete: Bool {
            completedRequiredCount == requiredCount && requiredCount > 0
        }
    }

    // MARK: - Core logic for a single habit
    static func summarize(links: [HabitReminderLink], reminders: [EKReminder]) -> Summary {
        // Only consider links that are marked as required.
        let requiredLinks = links.filter { $0.isRequired }
        let requiredCount = requiredLinks.count

        if requiredCount == 0 {
            return Summary(requiredCount: 0, completedRequiredCount: 0)
        }

        // Build lookup dictionary of reminders by their calendarItemIdentifier.
        let remindersById: [String: EKReminder] = Dictionary(
            uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) }
        )

        // Count how many required reminders are completed.
        var completedRequiredCount = 0

        for link in requiredLinks {
            // `reminderIdentifier` is optional on the Core Data entity.
            guard let id = link.reminderIdentifier,
                  let reminder = remindersById[id] else {
                continue // No matching reminder in this fetch.
            }

            if reminder.isCompleted {
                completedRequiredCount += 1
            }
        }

        return Summary(
            requiredCount: requiredCount,
            completedRequiredCount: completedRequiredCount
        )
    }

    // MARK: - Debug helper for ALL habits
    static func debugSummaries(
        in context: NSManagedObjectContext,
        reminders: [EKReminder]
    ) {
        print("===== Habit completion summaries (debug) =====")

        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let habits = try context.fetch(request)

            if habits.isEmpty {
                print("No Habit rows in Core Data.")
                print("===== end summaries =====")
                return
            }

            for habit in habits {
                // Convert NSSet -> Swift [HabitReminderLink]
                let linksSet = habit.reminderLinks as? Set<HabitReminderLink> ?? []
                let links = Array(linksSet)

                let summary = summarize(links: links, reminders: reminders)
                let name = habit.name ?? "Unnamed"

                print("""
                Habit: \(name)
                  required reminders: \(summary.requiredCount)
                  completed required: \(summary.completedRequiredCount)
                  isComplete: \(summary.isComplete)
                """)
            }

            print("===== end summaries =====")
        } catch {
            print("⚠️ HabitCompletionEngine: failed to fetch habits: \(error)")
        }
    }
    /// Compute and store HabitCompletion rows for **today** for every Habit,
    /// based on the given list of Reminders.
    static func upsertCompletionsForToday(
        in context: NSManagedObjectContext,
        reminders: [EKReminder]
    ) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 1. Fetch all habits
        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let habits = try context.fetch(request)

            if habits.isEmpty {
                print("⚠️ HabitCompletionEngine: no habits found when upserting completions.")
                return
            }

            for habit in habits {
                // Convert NSSet -> [HabitReminderLink]
                let linkSet = habit.reminderLinks as? Set<HabitReminderLink> ?? []
                let links = Array(linkSet)

                // Re-use the same summary logic used by debugSummaries
                let summary = summarize(links: links, reminders: reminders)

                // 2. Fetch (or create) the HabitCompletion for (habit, today)
                let completionRequest: NSFetchRequest<HabitCompletion> = HabitCompletion.fetchRequest()
                completionRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "habit == %@", habit),
                    NSPredicate(format: "date == %@", today as NSDate)
                ])
                completionRequest.fetchLimit = 1

                let completion: HabitCompletion
                if let existing = try context.fetch(completionRequest).first {
                    completion = existing
                } else {
                    completion = HabitCompletion(context: context)
                    completion.habit = habit
                    completion.date = today
                }

                // 3. Update fields from the summary
                completion.totalRequired = Int16(summary.requiredCount)
                completion.completedRequired = Int16(summary.completedRequiredCount)
                completion.isComplete = summary.isComplete
                completion.source = "reminders"

                // Optional: debug log per-habit
                print("""
                💾 HabitCompletion upserted:
                  habit = \(habit.name ?? "Unnamed")
                  date = \(today)
                  totalRequired = \(completion.totalRequired)
                  completedRequired = \(completion.completedRequired)
                  isComplete = \(completion.isComplete)
                """)
            }

            // 4. Save changes if needed
            if context.hasChanges {
                try context.save()
                print("✅ HabitCompletionEngine: saved completions for today.")
            } else {
                print("ℹ️ HabitCompletionEngine: no changes to save for today.")
            }
        } catch {
            print("❌ HabitCompletionEngine: failed to upsert completions for today: \(error)")
        }
    }
}
