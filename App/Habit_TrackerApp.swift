import SwiftUI
import CoreData

@main
struct Habit_TrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    let persistenceController = PersistenceController.shared

    @StateObject private var eventKitSyncCoordinator = EventKitSyncCoordinator()

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environment(
                \.managedObjectContext,
                persistenceController.container.viewContext
            )
            .environmentObject(eventKitSyncCoordinator)
            .task {
                eventKitSyncCoordinator.startObserving()
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
