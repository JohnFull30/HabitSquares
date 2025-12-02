import Foundation
import CoreData

struct HabitSeeder {
    static func insertSampleHabitsIfNeeded(in context: NSManagedObjectContext) {
        // 🚫 Seeder temporarily disabled while we debug the Core Data setup.
        // Leave this as a no-op so it can't crash the app.
        print("HabitSeeder.insertSampleHabitsIfNeeded: (temporarily disabled)")
    }
}
