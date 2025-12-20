//
//  AddRemindersSheet.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/20/25.
//


import SwiftUI
import CoreData
import EventKit

struct AddRemindersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @ObservedObject var habit: Habit
    @StateObject private var client = RemindersClient()

    @State private var searchText = ""
    @State private var selectedIDs = Set<String>()
    @State private var requiredByID: [String: Bool] = [:]

    private var filteredReminders: [EKReminder] {
        let base = client.reminders
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter { ($0.title).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let msg = client.errorMessage {
                    ContentUnavailableView(
                        "Reminders Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(msg)
                    )
                } else if !client.isAuthorized && client.reminders.isEmpty {
                    ContentUnavailableView(
                        "Need Reminders Access",
                        systemImage: "checklist",
                        description: Text("Enable Reminders access to link items to this habit.")
                    )
                } else {
                    List {
                        ForEach(filteredReminders, id: \.calendarItemIdentifier) { r in
                            row(reminder: r)
                        }
                    }
                    .searchable(text: $searchText)
                }
            }
            .navigationTitle("Add Reminders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLinks()
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .task {
                await client.fetchAllReminders()
                seedInitialSelectionsFromExistingLinks()
            }
        }
    }

    @ViewBuilder
    private func row(reminder: EKReminder) -> some View {
        let id = reminder.calendarItemIdentifier
        let isSelected = selectedIDs.contains(id)

        Button {
            toggleSelection(id: id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .lineLimit(1)

                    if isSelected {
                        Text((requiredByID[id] ?? true) ? "Required" : "Optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Button((requiredByID[id] ?? true) ? "Required" : "Optional") {
                        requiredByID[id] = !((requiredByID[id] ?? true))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            requiredByID.removeValue(forKey: id)
        } else {
            selectedIDs.insert(id)
            requiredByID[id] = true // default
        }
    }

    private func seedInitialSelectionsFromExistingLinks() {
        let existing = (habit.reminderLinks as? Set<HabitReminderLink>) ?? []
        for link in existing {
            if let id = link.ekReminderID, !id.isEmpty {
                selectedIDs.insert(id)
                requiredByID[id] = link.isRequired
            }
        }
    }

    private func saveLinks() {
        let existing = (habit.reminderLinks as? Set<HabitReminderLink>) ?? []
        let existingIDs = Set(existing.compactMap { $0.ekReminderID })

        // 1) Add new links for any selected reminders not already linked
        for r in client.reminders {
            let id = r.calendarItemIdentifier
            guard selectedIDs.contains(id) else { continue }
            guard !existingIDs.contains(id) else { continue }

            let link = HabitReminderLink(context: context)
            link.id = UUID()
            link.habit = habit
            link.ekReminderID = id
            link.title = r.title
            link.isRequired = requiredByID[id] ?? true
        }

        // 2) Update existing links' required flag/title if they are still selected
        for link in existing {
            guard let id = link.ekReminderID else { continue }
            guard selectedIDs.contains(id) else { continue }
            link.isRequired = requiredByID[id] ?? link.isRequired

            // Optional: keep title in sync if reminder title changed
            if let latest = client.reminders.first(where: { $0.calendarItemIdentifier == id }) {
                link.title = latest.title
            }
        }

        // 3) (Optional behavior) If user unselects a previously-linked reminder, remove that link
        // Comment this out if you prefer "unselect doesn't delete"
        for link in existing {
            guard let id = link.ekReminderID else { continue }
            if !selectedIDs.contains(id) {
                context.delete(link)
            }
        }

        do {
            try context.save()
        } catch {
            print("Failed saving reminder links: \(error)")
        }
    }
}
