import SwiftUI
import CoreData
import EventKit

struct EditHabitSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var eventKitSyncCoordinator: EventKitSyncCoordinator

    @ObservedObject var habit: Habit

    @FetchRequest private var reminderLinks: FetchedResults<HabitReminderLink>

    @State private var name: String = ""
    @State private var showAddRemindersSheet = false

    @State private var reminderStore = EKEventStore()
    @State private var editingReminder: EKReminder?
    @State private var editingLink: HabitReminderLink?
    @State private var editingReminderIsRequiredForGreenSquare = true
    @State private var linkPendingDelete: HabitReminderLink?

    init(habit: Habit) {
        self.habit = habit
        _reminderLinks = FetchRequest<HabitReminderLink>(
            sortDescriptors: [],
            predicate: NSPredicate(format: "habit == %@", habit)
        )
    }

    private var sortedReminderLinks: [HabitReminderLink] {
        reminderLinks.sorted {
            linkDisplayTitle($0).localizedLowercase < linkDisplayTitle($1).localizedLowercase
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit Name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                }

                Section("Linked Reminders") {
                    if sortedReminderLinks.isEmpty {
                        Text("No reminders linked yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedReminderLinks, id: \.objectID) { link in
                            linkedReminderRow(link)
                        }
                    }

                    Button {
                        showAddRemindersSheet = true
                    } label: {
                        Label("Add Reminders", systemImage: "plus.circle")
                    }
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
                            eventKitSyncCoordinator.refreshNow()
                            dismiss()
                        } catch {
                            print("✗ EditHabitSheet save failed:", error.localizedDescription)
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = habit.name ?? ""
            }
            .sheet(isPresented: $showAddRemindersSheet) {
                AddRemindersSheet(habit: habit)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(
                isPresented: Binding(
                    get: { editingReminder != nil },
                    set: { newValue in
                        if !newValue {
                            editingReminder = nil
                            editingLink = nil
                        }
                    }
                )
            ) {
                if let editingReminder {
                    NewReminderSheet(
                        eventStore: reminderStore,
                        habitName: habit.name ?? "Habit",
                        initialCalendarID: editingReminder.calendar.calendarIdentifier,
                        existingReminder: editingReminder,
                        existingIsRequiredForGreenSquare: editingReminderIsRequiredForGreenSquare
                    ) { updatedReminder, isRequired in
                        handleEditedReminderSave(updatedReminder, isRequired: isRequired)
                    }
                }
            }
            
            .confirmDelete(
                item: $linkPendingDelete,
                title: "Delete linked reminder?",
                message: "This removes the reminder from this habit. It does not delete the reminder from Apple Reminders.",
                confirmTitle: "Delete Link"
            ) { link in
                deleteLinkedReminder(link)
            }
        }
    }

    // MARK: - Linked reminder row

    @ViewBuilder
    private func linkedReminderRow(_ link: HabitReminderLink) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(linkDisplayTitle(link))
                    .font(.body)

                HStack(spacing: 6) {
                    if let calendarTitle = linkCalendarTitle(link), !calendarTitle.isEmpty {
                        Text(calendarTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(link.isRequired ? "Required" : "Optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    beginEditing(link: link)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    linkPendingDelete = link                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                beginEditing(link: link)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                linkPendingDelete = link            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Display helpers

    private func linkDisplayTitle(_ link: HabitReminderLink) -> String {
        let t = (link.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Reminder" : t
    }

    private func linkCalendarTitle(_ link: HabitReminderLink) -> String? {
        guard link.entity.propertiesByName["calendarTitle"] != nil else { return nil }
        let title = (link.value(forKey: "calendarTitle") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty == false) ? title : nil
    }

    private func linkStoredStableIdentifier(_ link: HabitReminderLink) -> String? {
        if let id = link.reminderIdentifier, !id.isEmpty {
            return id
        }

        if link.entity.propertiesByName["reminderId"] != nil,
           let id = link.value(forKey: "reminderId") as? String,
           !id.isEmpty {
            return id
        }

        if link.entity.propertiesByName["reminderID"] != nil,
           let id = link.value(forKey: "reminderID") as? String,
           !id.isEmpty {
            return id
        }

        return nil
    }

    // MARK: - Editing

    private func beginEditing(link: HabitReminderLink) {
        Task {
            let granted = await requestReminderAccessIfNeeded()
            guard granted else { return }

            guard let storedID = linkStoredStableIdentifier(link) else {
                print("✗ EditHabitSheet: no stored reminder identifier found on link")
                return
            }

            let reminders = await fetchAllRemindersForEditing()

            let match = reminders.first { reminder in
                if let stamped = stampedUUID(from: reminder), stamped == storedID {
                    return true
                }

                if let externalID = reminder.calendarItemExternalIdentifier, externalID == storedID {
                    return true
                }

                return reminder.calendarItemIdentifier == storedID
            }

            guard let match else {
                print("✗ EditHabitSheet: could not resolve EventKit reminder for link ID \(storedID)")
                return
            }

            await MainActor.run {
                editingLink = link
                editingReminder = match
                editingReminderIsRequiredForGreenSquare = link.isRequired
            }
        }
    }

    private func handleEditedReminderSave(_ updatedReminder: EKReminder, isRequired: Bool) {
        guard let editingLink else { return }

        editingLink.isRequired = isRequired
        editingLink.title = updatedReminder.title

        if editingLink.entity.propertiesByName["required"] != nil {
            editingLink.setValue(isRequired, forKey: "required")
        }

        if editingLink.entity.propertiesByName["calendarTitle"] != nil {
            editingLink.setValue(updatedReminder.calendar.title, forKey: "calendarTitle")
        }

        do {
            try viewContext.save()
        } catch {
            print("✗ EditHabitSheet: failed saving edited link metadata:", error.localizedDescription)
        }

        Task { @MainActor in
            await ReminderMetadataRefresher.shared.refreshLinkTitles(in: viewContext)
            HabitCompletionEngine.syncTodayFromReminders(in: viewContext, includeCompleted: true)
            WidgetRefresh.push(viewContext)
            eventKitSyncCoordinator.refreshNow()

            editingReminder = nil
            self.editingLink = nil
        }
    }

    // MARK: - Delete

    private func deleteLinkedReminder(_ link: HabitReminderLink) {
        viewContext.delete(link)

        do {
            try viewContext.save()
            HabitCompletionEngine.syncTodayFromReminders(in: viewContext, includeCompleted: true)
            WidgetRefresh.push(viewContext)
            eventKitSyncCoordinator.refreshNow()
        } catch {
            print("✗ EditHabitSheet: failed deleting linked reminder:", error.localizedDescription)
        }
    }

    // MARK: - EventKit helpers

    private func requestReminderAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            return true

        case .writeOnly:
            return false

        case .notDetermined:
            if #available(iOS 17.0, *) {
                do { return try await reminderStore.requestFullAccessToReminders() }
                catch { return false }
            } else {
                return await withCheckedContinuation { cont in
                    reminderStore.requestAccess(to: .reminder) { granted, _ in
                        cont.resume(returning: granted)
                    }
                }
            }

        case .denied, .restricted:
            return false

        @unknown default:
            return false
        }
    }

    private func fetchAllRemindersForEditing() async -> [EKReminder] {
        let calendars = reminderStore.calendars(for: .reminder)
        let predicate = reminderStore.predicateForReminders(in: calendars)

        return await withCheckedContinuation { cont in
            reminderStore.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
    }

    private func stampedUUID(from reminder: EKReminder) -> String? {
        guard let url = reminder.url else { return nil }
        guard url.scheme?.lowercased() == "habitsquares" else { return nil }
        guard url.host?.lowercased() == "reminder-link" else { return nil }

        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.isEmpty ? nil : raw
    }
}
