import Foundation
import EventKit
import CoreData

/// Core logic for figuring out if a habit is "complete"
/// based on its linked Apple Reminders.
struct HabitCompletionEngine {

    struct Summary {
        /// How many required reminder links this habit has
        let requiredCount: Int
        /// How many of those required reminders are completed
        let completedRequiredCount: Int

        /// A habit is considered complete only when:
        /// - there is at least one required reminder, and
        /// - all required reminders are completed.
        var isComplete: Bool {
            requiredCount > 0 && completedRequiredCount == requiredCount
        }
    }

    /// Compute completion summary for **one habit** given:
    /// - the HabitReminderLink rows for that habit
    /// - the EKReminders we fetched from ReminderService
    static func summarize(
        links: [HabitReminderLink],
        reminders: [EKReminder]
    ) -> Summary {

        // Only consider required links
        let requiredLinks = links.filter { $0.isRequired }
        let requiredCount = requiredLinks.count

        // If there are no required reminders, this habit
        // can never be considered "complete".
        if requiredCount == 0 {
            return Summary(requiredCount: 0, completedRequiredCount: 0)
        }

        // Build a lookup dictionary: reminderID -> EKReminder
        let remindersById: [String: EKReminder] = Dictionary(
            uniqueKeysWithValues: reminders.map { ($0.calendarItemIdentifier, $0) }
        )

        // Count how many required reminders are completed
        var completedRequiredCount = 0

        for link in requiredLinks {
            // NOTE: We use KVC here instead of a generated property
            // because Xcode hasn't surfaced `reminderIdentifier`
            // as a Swift property yet.
            guard
                let id = link.value(forKey: "reminderIdentifier") as? String,
                let reminder = remindersById[id]
            else {
                // No matching reminder in this fetch; skip
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
                print("⟡ No Habit rows in Core Data.")
            }

            for habit in habits {
                // Core Data relationship `reminderLinks` is an NSSet;
                // convert to a Swift Set<HabitReminderLink> then Array.
                let linkSet = habit.reminderLinks as? Set<HabitReminderLink> ?? []
                let links = Array(linkSet)

                let summary = summarize(links: links, reminders: reminders)
                let name = habit.name ?? "Unnamed"

                print("""
                Habit: \(name)
                  required reminders: \(summary.requiredCount)
                  completed required reminders: \(summary.completedRequiredCount)
                  isComplete: \(summary.isComplete)
                """)
            }

            print("===== end summaries =====")

        } catch {
            print("⚠️ HabitCompletionEngine: failed to fetch habits: \(error)")
        }
    }
}
