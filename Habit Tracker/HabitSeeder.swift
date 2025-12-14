import Foundation
import CoreData

struct HabitSeeder {
    // Sample data seeding (currently disabled)
    static func insertSampleHabitsIfNeeded(in context: NSManagedObjectContext) {
        print("⚠️ HabitSeeder disabled – no sample data inserted")
    }

    // Debug helper: make sure the 'Code' reminder is linked to the 'Code' habit.
    static func ensureCodeReminderLink(
        in context: NSManagedObjectContext,
        forReminderIdentifier identifier: String
    ) {
        // 1) Find the target habit by name
        let targetHabitName = "Code"

        let habitRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
        habitRequest.predicate = NSPredicate(format: "name == %@", targetHabitName)
        habitRequest.fetchLimit = 1

        guard let habit = try? context.fetch(habitRequest).first else {
            print("⚠️ HabitSeeder.ensureCodeReminderLink: '\(targetHabitName)' habit not found")
            return
        }

        // 2) Look for any existing link between this habit and this reminder
        let linkRequest: NSFetchRequest<HabitReminderLink> = HabitReminderLink.fetchRequest()
        linkRequest.predicate = NSPredicate(
            format: "habit == %@ AND reminderIdentifier == %@",
            habit,
            identifier
        )
        linkRequest.fetchLimit = 1

        let existingLink = try? context.fetch(linkRequest).first

        // 3) Create or update the link
        let link = existingLink ?? HabitReminderLink(context: context)
        link.habit = habit
        link.reminderIdentifier = identifier
        link.isRequired = true
        link.title = "Code"

        do {
            try context.save()
            print("✅ HabitSeeder.ensureCodeReminderLink: linked '\(link.title ?? "Code")' reminder to '\(targetHabitName)' habit")
        } catch {
            print("❌ HabitSeeder.ensureCodeReminderLink: failed with error: \(error)")
        }
    }
}
