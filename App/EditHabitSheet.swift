//
//  EditHabitSheet.swift
//  Habit Tracker
//
//  Created by John Fuller on 1/14/26.
//


//
//  EditHabitSheet.swift
//  Habit Tracker
//

import SwiftUI
import CoreData

struct EditHabitSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var habit: Habit

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit Name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                }
            }
            .navigationTitle("Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        habit.name = trimmed
                        do {
                            try viewContext.save()
                            
                            WidgetRefresh.push(viewContext)

                            dismiss()
                        } catch {
                            // Keep it simple for now — you can add an alert later if you want
                            print("✗ EditHabitSheet save failed:", error.localizedDescription)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // prefill from Core Data
                name = habit.name ?? ""
            }
        }
    }
}
