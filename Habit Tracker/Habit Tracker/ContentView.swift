import SwiftUI
import CoreData
import EventKit

// MARK: - Main Habit List / Heatmap

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Pull Habit rows from Core Data (typed to Habit NSManagedObject)
    @FetchRequest(
        entity: Habit.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Habit.name, ascending: true)],
        animation: .default
    )
    private var habitResults: FetchedResults<Habit>

    @State private var isShowingAddHabit = false
    @State private var isShowingReminders = false

    // Map Core Data habits -> HabitModel for the heatmap UI
    private var habitModels: [HabitModel] {
        let demo = HabitDemoData.makeSampleHabits()

        // If Core Data is empty, just show the demo data
        guard !habitResults.isEmpty else {
            return demo
        }

        // Pair each Core Data habit with a demo habit to reuse the 30-day pattern
        return Array(habitResults.enumerated().map { index, habit in
            let base = index < demo.count ? demo[index] : demo[index % demo.count]

            let id = habit.id ?? base.id
            let name = habit.name ?? base.name
            let colorHex = habit.colorHex ?? base.colorHex
            let trackingMode = base.trackingMode    // <- only use demo tracking mode for now
            let days = base.days // TODO: later map real HabitCompletion rows
            
            return HabitModel(
                id: id,
                name: name,
                colorHex: colorHex,
                trackingMode: trackingMode,
                days: days
            )
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(habitModels) { habit in
                        HabitHeatmapView(habit: habit)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
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

                // “+” button on the right
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddHabit) {
                AddHabitView()
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $isShowingReminders) {
                RemindersDebugView()   // renamed to avoid conflict
            }
            .onAppear {
                logCoreDataState()
                // We no longer call ReminderService.checkAuthorization here,
                // because that method does not exist in your ReminderService.
            }
        }
    }

    // MARK: - Debug helpers

    private func logCoreDataState() {
        print("Core Data store loaded:")
        if let storeDescription = PersistenceController.shared
            .container.persistentStoreDescriptions.first,
           let url = storeDescription.url {
            print(url.path)
        }

        print("----- Core Data habits -----")
        for habit in habitResults {
            let name = habit.name ?? "Unnamed"
            print("• \(name)")
        }
        print("----- end -----")
    }
}

// MARK: - Add Habit Screen

struct AddHabitView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var trackingMode: String = "manual"

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("Name", text: $name)
                }

                Section("Tracking") {
                    Picker("Mode", selection: $trackingMode) {
                        Text("Manual").tag("manual")
                        Text("Goal-based").tag("goal")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveHabit()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }


    private func saveHabit() {
        // Create a new Habit managed object using the generated class
        let habit = Habit(context: viewContext)

        habit.id = UUID()
        habit.name = name
        habit.colorHex = "#22CC55"          // temporary default color
        habit.reminderIdentifier = nil      // we'll use HabitReminderLink instead

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("❌ Failed to save new habit: \(error)")
        }
    }
}
// MARK: - Simple Reminders Debug Screen

/// Renamed from `RemindersListView` to avoid conflicting with any existing file.
struct RemindersDebugView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var reminders: [EKReminder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                } else if isLoading {
                    ProgressView("Loading Reminders…")
                } else if reminders.isEmpty {
                    Text("No outstanding Reminders found.")
                        .foregroundColor(.secondary)
                } else {
                    List(reminders, id: \.calendarItemIdentifier) { reminder in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title)
                                .font(.headline)

                            if let date = reminder.dueDateComponents?.date {
                                Text(date.formatted(date: .abbreviated,
                                                    time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                loadReminders()
            }
        }
    }

    private func loadReminders() {
        isLoading = true
        errorMessage = nil

        // Use the labelled parameter `completion:` to match your ReminderService API
        ReminderService.shared.fetchOutstandingReminders(completion: { fetched in
            Task { @MainActor in
                self.reminders = fetched
                self.isLoading = false
            }
        })
    }
}
