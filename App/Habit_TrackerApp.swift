import SwiftUI
import CoreData

@main
struct Habit_TrackerApp: App {
    // Core Data stack
    let persistenceController = PersistenceController.shared

    var body: some Scene {
           WindowGroup {
               ContentView()
                   .environment(\.managedObjectContext,
                                 persistenceController.container.viewContext)
                   .onAppear {
                       // Ask for Reminders permission once
                       ReminderService.shared.requestAccessIfNeeded { granted in
                           print("Reminders access granted? \(granted)")
                       }
                   }
           }
       }
}
