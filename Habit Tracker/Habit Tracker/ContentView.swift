import SwiftUI
import CoreData
import EventKit

// MARK: - Main Habit List / Heatmap

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Pull Habit rows from Core Data (typed to the Habit NSManagedObject)
    @FetchRequest(
        entity: Habit.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Habit.name, ascending: true)],
        animation: .default
    )
    private var habitResults: FetchedResults<Habit>

    @State private var isShowingAddHabit = false
    @State private var isShowingReminders = false

    // Map Core Data Habits -> HabitModel for the heatmap UI
    private var habitModels: [HabitModel] {
        let demo = HabitDemoData.makeSampleHabits()

        // If Core Data is empty, just show the demo data
        guard !habitResults.isEmpty else {
            return demo
        }

        // Pair each Core Data habit with a demo habit to reuse the 30-day pattern
        return Array(habitResults.enumerated()).map { index, habit in
            let base = index < demo.count ? demo[index] : demo[index % demo.count]

            let id = habit.id ?? base.id
            let name = habit.name ?? base.name
            let colorHex = habit.colorHex ?? base.colorHex
            let trackingMode = habit.trackingMode ?? base.trackingMode
            let days = base.days // TODO: later map real HabitCompletion rows

            return HabitModel(
                id: id,
                name: name,
                colorHex: colorHex,
                trackingMode: trackingMode,
                days: days
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(habitModels) { habit in
                    HabitHeatmapView(habit: habit)
                }
            }
            .listStyle(.plain)
            .navigationTitle("HabitSquares")
            .toolbar {
                // "+" button on the right – add a new habit
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAddHabit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                // "list" button on the left – open Reminders debug sheet
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingReminders = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                }
            }
        }
        // Add Habit sheet
        .sheet(isPresented: $isShowingAddHabit) {
            AddHabitView()
                .environment(\.managedObjectContext, viewContext)
        }
        // Simple Reminders debug sheet
        .sheet(isPresented: $isShowingReminders) {
            RemindersListView()
        }
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
                    Button("Cancel") {
                        dismiss()
                    }
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
        // Create a new Habit row in Core Data
        guard let entity = NSEntityDescription.entity(forEntityName: "Habit",
                                                      in: viewContext) else {
            print("⚠️ Could not find Habit entity")
            return
        }

        let habit = NSManagedObject(entity: entity, insertInto: viewContext)
        habit.setValue(UUID(), forKey: "id")
        habit.setValue(name, forKey: "name")
        habit.setValue("#22C55E", forKey: "colorHex")        // default green
        habit.setValue(trackingMode, forKey: "trackingMode")

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Failed to save new habit: \(error)")
        }
    }
}

// MARK: - Simple Reminders Debug Screen

struct RemindersListView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var reminders: [EKReminder] = []
    @State private var isLoading: Bool = true
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
                                Text(date.formatted(date: .abbreviated, time: .shortened))
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
                    Button("Close") {
                        dismiss()
                    }
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

        ReminderService.shared.fetchOutstandingReminders { fetched in
            // Hop back to the main actor for UI updates
            Task { @MainActor in
                self.reminders = fetched
                // If you ever add error handling inside ReminderService,
                // you can update errorMessage here.
                self.isLoading = false
            }
        }
    }
}
