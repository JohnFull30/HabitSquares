import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase

    // Core Data fetch for all habits
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Habit.name, ascending: true)],
        animation: .default
    )
    private var habitResults: FetchedResults<Habit>

    // Which sheet is currently active
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case addHabit
        case reminders

        var id: Int {
            switch self {
            case .addHabit: return 0
            case .reminders: return 1
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if habitResults.isEmpty {
                    VStack(spacing: 12) {
                        Text("No habits yet.")
                            .font(.headline)
                        Text("Tap the + button to add your first habit.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(habitResults) { habit in
                            HabitHeatmapView(habit: habit)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("HabitSquares")
            .toolbar {
                // Left: Reminders debug / linking
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if !habitResults.isEmpty {
                            activeSheet = .reminders
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .disabled(habitResults.isEmpty)
                }

                // Right: Add habit
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .addHabit
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        // Single sheet that switches on ActiveSheet
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addHabit:
                AddHabitView()
                    .environment(\.managedObjectContext, viewContext)

            case .reminders:
                if let firstHabit = habitResults.first {
                    ReminderListView(habit: firstHabit)
                        .environment(\.managedObjectContext, viewContext)
                } else {
                    Text("No habits yet. Add one first.")
                        .presentationDetents([.medium])
                }
            }
        }
        .onAppear {
            logCoreDataState()
            syncTodayFromReminders()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                syncTodayFromReminders()
            }
        }
    }

    // MARK: - Sync Reminders → (future) HabitCompletion

    private func syncTodayFromReminders() {
        ReminderService.shared.fetchTodayReminders(includeCompleted: true) { fetched in
            Task { @MainActor in
                // TODO: Wire back into HabitCompletionEngine when we confirm the exact API.
                // For now, just log so we can verify this is being called.
                print("🔄 syncTodayFromReminders: fetched \(fetched.count) reminders for today.")
            }
        }
    }

    // MARK: - Debug helpers

    private func logCoreDataState() {
        print("===== Core Data habits =====")
        for habit in habitResults {
            print("• \(habit.name ?? "<Unnamed>")")
        }
        print("===== end =====")
    }
}
