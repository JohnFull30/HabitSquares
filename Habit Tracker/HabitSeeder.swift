import Foundation
import CoreData

struct HabitSeeder {

    // MARK: - Sample data seeding (currently disabled)

    /// Seeder currently disabled. Left here as a placeholder
    /// so the app doesn’t try to insert demo data on launch.
    static func insertSampleHabitsIfNeeded(in context: NSManagedObjectContext) {
        print("HabitSeeder disabled — no sample data inserted")
    }

    // MARK: - Debug helper: link "Code" reminder to a habit

    /// Ensures that the "Code" reminder for today is linked to the
    /// "Checking" habit via a HabitReminderLink row.
    ///
    /// This is used only from `ReminderListView` as a debug helper so that
    /// HabitCompletionEngine has at least one real link to work with.
    static func ensureCodeReminderLink(
        in context: NSManagedObjectContext,
        forReminderIdentifier identifier: String
    ) {
        context.perform {
            do {
                // 1) Find the "Checking" habit
                let habitRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
                habitRequest.predicate = NSPredicate(format: "name == %@", "Checking")
                habitRequest.fetchLimit = 1

                guard let habit = try context.fetch(habitRequest).first else {
                    print("⚠️ HabitSeeder.ensureCodeReminderLink: 'Checking' habit not found")
                    return
                }

                // 2) See if a link already exists for this habit + reminder id
                let linkRequest: NSFetchRequest<HabitReminderLink> = HabitReminderLink.fetchRequest()
                linkRequest.predicate = NSPredicate(
                    format: "habit == %@ AND reminderIdentifier == %@",
                    habit,
                    identifier
                )
                linkRequest.fetchLimit = 1

                let existingLink = try context.fetch(linkRequest).first

                // 3) Create or update the link
                let link = existingLink ?? HabitReminderLink(context: context)
                link.habit = habit
                link.reminderIdentifier = identifier
                link.isRequired = true
                link.title = "Code"

                try context.save()
                print("✅ HabitSeeder.ensureCodeReminderLink: linked 'Code' reminder to 'Checking' habit")
            } catch {
                print("❌ HabitSeeder.ensureCodeReminderLink: failed with error: \(error)")
            }
        }
    }
}
