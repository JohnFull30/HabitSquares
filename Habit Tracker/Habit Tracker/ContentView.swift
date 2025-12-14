import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Core Data fetch for all habits
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Habit.name, ascending: true)],
        animation: .default
    )
    private var habitResults: FetchedResults<Habit>

    @State private var isShowingReminders = false
    @State private var isShowingAddHabit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(habitResults) { habit in
                        HabitHeatmapView(habit: habit)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("HabitSquares")
            .toolbar {
                // Debug “list” button on the left
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingReminders = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }

                // "+" button on the right
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            // Add Habit sheet
            .sheet(isPresented: $isShowingAddHabit) {
                AddHabitView()
                    .environment(\.managedObjectContext, viewContext)
            }
            // Reminders debug sheet
            .sheet(isPresented: $isShowingReminders) {
                ReminderListView()
            }
            .onAppear {
                logCoreDataState()
            }
        }
    }

    // MARK: - Debug helpers

    private func logCoreDataState() {
        print("✅ Core Data store loaded:")

        if let storeDescription = PersistenceController.shared
            .container
            .persistentStoreDescriptions
            .first,
           let url = storeDescription.url
        {
            print(url.path)
        }

        let request: NSFetchRequest<Habit> = Habit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let context = PersistenceController.shared.container.viewContext
            let habits = try context.fetch(request)

            print("===== Core Data habits =====")
            for habit in habits {
                let name = habit.name ?? "Unnamed"
 
            }
            print("===== end =====")
        } catch {
            print("⚠️ logCoreDataState: failed to fetch habits: \(error)")
        }
    }
}
