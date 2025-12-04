import Foundation
import CoreData

struct HabitSeeder {
    /// Seeder currently disabled. Left here as a placeholder
    /// so the app doesn't try to insert demo data on launch.
    static func insertSampleHabitsIfNeeded(in context: NSManagedObjectContext) {
        print("HabitSeeder disabled – no sample data inserted")
    }
}
