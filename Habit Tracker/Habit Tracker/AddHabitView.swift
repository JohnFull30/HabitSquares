import SwiftUI
import CoreData

struct AddHabitView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var trackingMode: String = "manual"   // "manual" / "allReminders"

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Habit name", text: $name)
                }

                Section("Tracking Mode") {
                    Picker("Tracking Mode", selection: $trackingMode) {
                        Text("Manual").tag("manual")
                        Text("All Reminders").tag("allReminders")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Add Habit")
            .toolbar {
                // Cancel
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                // Save
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveHabit()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveHabit() {
        let habit = Habit(context: viewContext)
        habit.id = UUID()
        habit.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.colorHex = "#22C55E" // temporary default green

        print("✅ AddHabitView.saveHabit: creating habit id=\(habit.objectID) name='\(habit.name ?? "<nil>")'")

        do {
            try viewContext.save()
            print("✅ AddHabitView.saveHabit: saved habit")
            dismiss()   // <- this is what closes the Add Habit sheet
        } catch {
            print("❌ AddHabitView.saveHabit: failed to save habit: \(error)")
        }
    }
}
