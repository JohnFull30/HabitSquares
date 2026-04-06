import SwiftUI
import CoreData

@main
struct Habit_TrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    let persistenceController = PersistenceController.shared

    @StateObject private var eventKitSyncCoordinator = EventKitSyncCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(
                    \.managedObjectContext,
                    persistenceController.container.viewContext
                )
                .environmentObject(eventKitSyncCoordinator)
                .task {
                    eventKitSyncCoordinator.startObserving()
                }
                .onAppear {
                    ReminderService.shared.requestAccessIfNeeded { granted in
                        print("Reminders access granted? \(granted)")
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }

                    Task { @MainActor in
                        eventKitSyncCoordinator.refreshNow()

                        await ReminderMetadataRefresher.shared.refreshLinkTitles(
                            in: persistenceController.container.viewContext
                        )
                    }
                }
        }
    }
}
