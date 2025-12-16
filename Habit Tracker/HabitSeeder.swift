import Foundation
import CoreData

/// Seeds demo habits and manages links between Habits and Apple Reminders.
struct HabitSeeder {

    // MARK: - Public seeding API

    /// Ensure there is at least one demo habit in the store.
    /// Call this once on app launch (usually from PersistenceController or App).
    static func ensureDemoHabits(in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
        fetchRequest.fetchLimit = 1

        let existingCount = (try? context.count(for: fetchRequest)) ?? 0
        guard existingCount == 0 else {
            // Already seeded
            return
        }

        let demoHabit = Habit(context: context)
        demoHabit.id = UUID()
        demoHabit.name = "Code"

        do {
            try context.save()
            print("✅ HabitSeeder.ensureDemoHabits: seeded demo habit '\(demoHabit.name ?? "Habit")'")
        } catch {
            print("❌ HabitSeeder.ensureDemoHabits: failed to save demo habits: \(error)")
        }
    }

    /// Backwards-compatible helper for the old “Code” habit.
    static func ensureCodeReminderLink(
        in context: NSManagedObjectContext,
        forReminderIdentifier identifier: String,
        reminderTitle: String
    ) {
        let habit = fetchOrCreateHabit(named: "Code", in: context)

        upsertLink(
            habit: habit,
            in: context,
            forReminderIdentifier: identifier,
            reminderTitle: reminderTitle
        )

        print("🔗 HabitSeeder.ensureCodeReminderLink: linked reminder '\(reminderTitle)' (\(identifier)) to habit '\(habit.name ?? "Code")'")
    }

    // MARK: - Generic link API (used by ReminderListView)

    /// Create or update a `HabitReminderLink` between a Habit and a specific
    /// Reminders identifier. This is what makes the reminder "count" for that habit.
    static func upsertLink(
        habit: Habit,
        in context: NSManagedObjectContext,
        forReminderIdentifier identifier: String,
        reminderTitle: String
    ) {
        // Look for an existing link between this habit and this reminder id
        let fetch: NSFetchRequest<HabitReminderLink> = HabitReminderLink.fetchRequest()
        fetch.predicate = NSPredicate(
            format: "habit == %@ AND reminderIdentifier == %@",
            habit,
            identifier
        )
        fetch.fetchLimit = 1

        let link: HabitReminderLink
        if let existing = (try? context.fetch(fetch))?.first {
            link = existing
        } else {
            link = HabitReminderLink(context: context)
            link.id = UUID()
            link.habit = habit
            link.reminderIdentifier = identifier
        }

        // Mark as required so it counts toward completion
        link.isRequired = true   // 🔑 this is what HabitCompletionEngine uses

        do {
            try context.save()
            print("✅ HabitSeeder.upsertLink: linked reminder '\(reminderTitle)' (\(identifier)) to habit '\(habit.name ?? "Habit")'")
        } catch {
            print("❌ HabitSeeder.upsertLink: failed to save link: \(error)")
        }
    }

    // MARK: - Private helpers

    /// Fetch an existing habit with the given name or create it if missing.
    private static func fetchOrCreateHabit(
        named name: String,
        in context: NSManagedObjectContext
    ) -> Habit {
        let fetchRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        fetchRequest.fetchLimit = 1

        if let existing = (try? context.fetch(fetchRequest))?.first {
            return existing
        }

        let habit = Habit(context: context)
        habit.id = UUID()
        habit.name = name

        do {
            try context.save()
            print("✅ HabitSeeder.fetchOrCreateHabit: created habit '\(name)'")
        } catch {
            print("❌ HabitSeeder.fetchOrCreateHabit: failed to save new habit '\(name)': \(error)")
        }

        return habit
    }
}
