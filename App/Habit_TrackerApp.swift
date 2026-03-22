import SwiftUI
import CoreData

@main
struct Habit_TrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(
                    \.managedObjectContext,
                    persistenceController.container.viewContext
                )
                .onAppear {
                    ReminderService.shared.requestAccessIfNeeded { granted in
                        print("Reminders access granted? \(granted)")
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }

                    Task { @MainActor in
                        await ReminderMetadataRefresher.shared.refreshLinkTitles(
                            in: persistenceController.container.viewContext
                        )
                    }
                }
        }
    }
}
