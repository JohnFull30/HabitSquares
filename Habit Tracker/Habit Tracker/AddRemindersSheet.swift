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

    // NEW: list filter (nil = All Lists)
    @State private var selectedListName: String? = nil

    // NEW: build list names from fetched reminders
    private var availableListNames: [String] {
        let names = Set(client.reminders.map { $0.calendar.title })
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredReminders: [EKReminder] {
        var items = client.reminders

        // Filter by list
        if let selectedListName {
            items = items.filter { $0.calendar.title == selectedListName }
        }

        // Filter by search
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            items = items.filter { $0.title.localizedCaseInsensitiveContains(q) }
        }

        return items
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
                        // NEW: list filter section
                        Section {
                            Picker("List", selection: Binding(
                                get: { selectedListName },
                                set: { selectedListName = $0 }
                            )) {
                                Text("All Lists").tag(String?.none)
                                ForEach(availableListNames, id: \.self) { name in
                                    Text(name).tag(String?.some(name))
                                }
                            }
                        }

                        Section {
                            ForEach(filteredReminders, id: \.calendarItemIdentifier) { r in
                                row(reminder: r)
                            }
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
        let required = requiredByID[id] ?? true

        Button {
            toggleSelection(id: id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .lineLimit(1)

                    // NEW: show list name (helps when “All Lists” is selected)
                    Text(reminder.calendar.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if isSelected {
                        Text(required ? "Required" : "Optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Button(required ? "Required" : "Optional") {
                        requiredByID[id] = !required
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

        // Add new links for any selected reminders not already linked
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

        // Update existing links' required flag/title if still selected
        for link in existing {
            guard let id = link.ekReminderID else { continue }
            guard selectedIDs.contains(id) else { continue }

            link.isRequired = requiredByID[id] ?? link.isRequired

            if let latest = client.reminders.first(where: { $0.calendarItemIdentifier == id }) {
                link.title = latest.title
            }
        }

        // If user unselects a previously-linked reminder, remove that link
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
