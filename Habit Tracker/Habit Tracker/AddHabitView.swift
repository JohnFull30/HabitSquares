//
//  AddHabitView.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/1/25.
//

import Foundation
import SwiftUI
import CoreData

struct AddHabitView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var trackingMode: String = "manual"

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
        let habit = Habit(context: viewContext)
        habit.name = name
        habit.colorHex = "#22C55E"           // temporary default green

        // Core Data Habit doesn't have this field yet, so skip for now.
        // habit.trackingMode = trackingMode  // "manual" or "allReminders"

        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("❌ Failed to save habit: \(error)")
        }
    }
}
