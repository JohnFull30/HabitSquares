import Foundation
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        // 🔑 Load whatever Core Data models exist in the main bundle
        guard let model = NSManagedObjectModel.mergedModel(from: [Bundle.main]) else {
            fatalError("❌ Could not load any Core Data models from main bundle")
        }

        // Use that model explicitly instead of looking up by name
        container = NSPersistentContainer(name: "HabitModel", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("❌ Unresolved Core Data error: \(error), \(error.userInfo)")
            } else {
                print("✅ Core Data store loaded: \(storeDescription.url?.absoluteString ?? "<no url>")")
            }
        }

        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
