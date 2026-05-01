import SwiftUI
import CoreData

struct AddHabitView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Habit name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Text("You can link Apple Reminders after creating this habit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Habit")
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func saveHabit() {
        let habit = Habit(context: viewContext)
        habit.id = UUID()
        habit.name = trimmedName
        habit.colorHex = "#22C55E"
        habit.createdAt = Date()

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("❌ AddHabitView.saveHabit: failed to save habit: \(error)")
        }
    }
}
