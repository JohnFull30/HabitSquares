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

    // MARK: - Sheet routing

    private enum ActiveSheet: Identifiable {
        case addHabit
        case reminders(Habit)

        // Unique ID so SwiftUI can distinguish sheets
        var id: String {
            switch self {
            case .addHabit:
                return "addHabit"
            case .reminders(let habit):
                // Use the Core Data objectID URI as a stable identifier
                return "reminders-\(habit.objectID.uriRepresentation().absoluteString)"
            }
        }
    }

    // MARK: - Body

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
                                // Make the whole row tappable, not just the text
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // 🔑 Open reminders sheet for *this* habit
                                    activeSheet = .reminders(habit)
                                }
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
                        // Keep a "debug" entry point: use the first habit if it exists
                        if let firstHabit = habitResults.first {
                            activeSheet = .reminders(firstHabit)
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

            case .reminders(let habit):
                // ✅ Now driven by whichever habit you tapped
                ReminderListView(habit: habit)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .onAppear {
            logCoreDataHabits("onAppear")
            syncTodayFromReminders()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                syncTodayFromReminders()
            }
        }
    }

    // MARK: - Sync Reminders → (future) HabitCompletion

    private func syncTodayFromReminders() {
        ReminderService.shared.fetchTodayReminders(includeCompleted: true) { fetched in
            Task { @MainActor in
                print("✅ syncTodayFromReminders: fetched \(fetched.count) reminders for today.")

                // When you’re ready, wire this back into HabitCompletionEngine
                HabitCompletionEngine.upsertCompletionsForToday(
                    in: viewContext,
                    reminders: fetched,
                )
            }
        }
    }

    // MARK: - Delete habits

    private func deleteHabits(at offsets: IndexSet) {
        for index in offsets {
            let habit = habitResults[index]
            viewContext.delete(habit)
        }

        do {
            try viewContext.save()
            print("✅ Deleted \(offsets.count) habit(s).")
        } catch {
            print("❌ Failed to delete habit(s): \(error)")
        }
    }

    // MARK: - Debug helpers

    private func logCoreDataHabits(_ label: String) {
        print("===== Core Data habits (\(label)) =====")
        for habit in habitResults {
            let id = habit.id?.uuidString ?? "nil"
            let name = habit.name ?? "<unnamed>"
            print(" - id: \(id), name: \(name)")
        }
        print("===== end =====")
    }
}
