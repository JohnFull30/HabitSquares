import Foundation
import CoreData
import EventKit

/// Computes whether a habit is "complete" based on its linked Reminders.
struct HabitCompletionEngine {

    /// Per-habit summary of required reminder links.
    struct Summary {
        /// How many linked reminders are marked as required.
        let requiredCount: Int

        /// How many of those required reminders are completed.
        let completedRequiredCount: Int

        /// A habit is complete only if:
        /// - it has at least one required reminder
        /// - and all required reminders are completed.
        var isComplete: Bool {
            requiredCount > 0 && completedRequiredCount == requiredCount
        }
    }

    // MARK: - Core logic for a single habit

    /// Compute a completion summary for a single habit based on its reminder links
    /// and the current outstanding / completed EKReminders.
    static func summarize(
        links: [HabitReminderLink],
        reminders: [EKReminder]
    ) -> Summary {

        // Only consider links that are marked as required.
        let requiredLinks = links.filter { $0.isRequired }
        let requiredCount = requiredLinks.count

        // If there are no required reminders, the habit can never be "complete".
        if requiredCount == 0 {
            return Summary(requiredCount: 0, completedRequiredCount: 0)
        }

        // Build a lookup dictionary of reminders by their calendarItemIdentifier.
        let remindersById: [String: EKReminder] = Dictionary(
            uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) }
        )

        // Count how many required links point to completed reminders.
        var completedRequiredCount = 0

        for link in requiredLinks {
            // reminderIdentifier is optional on the Core Data entity.
            guard let id = link.reminderIdentifier,
                  let reminder = remindersById[id] else {
                // No matching reminder available in this fetch.
                continue
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

    /// Debug function: prints a completion summary for every Habit row in Core Data.
    static func debugSummaries(
        in context: NSManagedObjectContext,
        reminders: [EKReminder]
    ) {
        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let habits = try context.fetch(request)

            print("===== Habit completion summaries (debug) =====")
            if habits.isEmpty {
                print("No Habit rows in Core Data.")
                print("===== end summaries =====")
                return
            }

            for habit in habits {
                // Core Data relationship `reminderLinks` is an NSSet; convert to Swift Set.
                let linkSet = habit.reminderLinks as? Set<HabitReminderLink> ?? []
                let links = Array(linkSet)

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
}
