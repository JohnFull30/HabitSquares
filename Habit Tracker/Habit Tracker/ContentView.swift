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
    
    private func logCoreDataHabits(_ label: String) {
        print("===== Core Data habits (\(label)) =====")
        for habit in habitResults {
            let id = habit.id?.uuidString ?? "nil"
            let name = habit.name ?? "<unnamed>"
            print("- id: \(id), name: \(name)")
        }
        print("===== end =====")
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
                        .onDelete(perform: deleteHabits)
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
                    .onDisappear {
                        // Sheet just closed (after Save or Cancel)
                        logCoreDataHabits("after AddHabitView")
                    }

            case .reminders:
                if let firstHabit = habitResults.first {
                    ReminderListView(habit: firstHabit)
                        .environment(\.managedObjectContext, viewContext)
                        .onDisappear {
                            logCoreDataHabits("after ReminderListView")
                        }
                } else {
                    Text("No habits yet. Add one first.")
                        .presentationDetents([.medium])
                }
            }
        }
        .onAppear {
            logCoreDataHabits("onAppear")
            syncTodayFromReminders()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                syncTodayFromReminders()
            }
        }
    }

    // MARK: - Sync Reminders → (future) HabitCompletion

    // MARK: – Sync Reminders → HabitCompletion
    private func syncTodayFromReminders() {
        ReminderService.shared.fetchTodayReminders(includeCompleted: true) { fetched in
            print("✅ syncTodayFromReminders: fetched \(fetched.count) reminders for today.")

            // IMPORTANT: actually update HabitCompletion here
            Task { @MainActor in
                HabitCompletionEngine.upsertCompletionsForToday(
                    in: viewContext,
                    reminders: fetched
                )
            }
        }
    }
    
    private func deleteHabits(at offsets: IndexSet) {
        // Grab the Habit objects at these indices and delete them
        for index in offsets {
            let habit = habitResults[index]
            viewContext.delete(habit)
        }

        do {
            try viewContext.save()
            print("🗑 Deleted \(offsets.count) habit(s).")
        } catch {
            viewContext.rollback()
            print("⚠️ Failed to delete habit(s): \(error)")
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

