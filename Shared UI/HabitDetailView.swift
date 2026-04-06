import SwiftUI
import CoreData
import EventKit

struct HabitDetailView: View {
    @ObservedObject var habit: Habit

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var eventKitSyncCoordinator: EventKitSyncCoordinator

    @State private var showingAddReminders = false

    @State private var reminderStore = EKEventStore()
    @State private var editingReminder: EKReminder?
    @State private var editingLink: HabitReminderLink?
    @State private var editingReminderIsRequiredForGreenSquare = true
    @State private var linkPendingDelete: HabitReminderLink?

    private var links: [HabitReminderLink] {
        let set = (habit.reminderLinks as? Set<HabitReminderLink>) ?? []
        return set.sorted { ($0.title ?? "") < ($1.title ?? "") }
    }

    var body: some View {
        List {
            Section("Linked Reminders") {
                if links.isEmpty {
                    Text("No reminders linked yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(links, id: \.objectID) { link in
                        linkRow(link)
                    }
                    .onDelete(perform: deleteLinks)
                }
                
                Button {
                    showingAddReminders = true
                } label: {
                    Label("Add Reminders", systemImage: "plus")
                }
            }
            
#if DEBUG
Section(footer:
    Text("Debug-only actions for seeding, syncing, and widget refresh.")
        .font(.caption)
) {
    DisclosureGroup {
        HabitDetailDebugToolsSection(
            onSeedThirtyDays: seedThirtyDays,
            onReloadWidget: reloadWidget,
            onRefreshReminderTitles: refreshReminderTitles
        )
        .padding(.top, 8)
    } label: {
        Label("Developer Tools", systemImage: "wrench.and.screwdriver")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
#endif
            }
        
        .navigationTitle(habit.name ?? "Habit")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddReminders) {
            AddRemindersSheet(habit: habit)
                .environment(\.managedObjectContext, context)
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

    // MARK: - Row

    @ViewBuilder
    private func linkRow(_ link: HabitReminderLink) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(for: link))
                    .lineLimit(1)

                Text(link.isRequired ? "Required" : "Optional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { link.isRequired },
                set: { newValue in
                    link.isRequired = newValue
                    saveContext()
                }
            ))
            .labelsHidden()
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                beginEditing(link: link)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                linkPendingDelete = link
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func displayTitle(for link: HabitReminderLink) -> String {
        let t = (link.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return "Reminder"
    }

    // MARK: - Editing

    private func beginEditing(link: HabitReminderLink) {
        Task {
            let granted = await requestReminderAccessIfNeeded()
            guard granted else { return }

            guard let storedID = linkStoredStableIdentifier(link) else {
                print("✗ HabitDetailView: no stored reminder identifier found on link")
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
                print("✗ HabitDetailView: could not resolve EventKit reminder for link ID \(storedID)")
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
        if let editingLink {
            editingLink.isRequired = isRequired
            editingLink.title = updatedReminder.title

            if editingLink.entity.propertiesByName["required"] != nil {
                editingLink.setValue(isRequired, forKey: "required")
            }

            if editingLink.entity.propertiesByName["calendarTitle"] != nil {
                editingLink.setValue(updatedReminder.calendar.title, forKey: "calendarTitle")
            }

            do {
                try context.save()
            } catch {
                print("✗ HabitDetailView: failed saving edited link metadata:", error.localizedDescription)
            }
        }

        Task { @MainActor in
            await ReminderMetadataRefresher.shared.refreshLinkTitles(in: context)
            HabitCompletionEngine.syncTodayFromReminders(in: context, includeCompleted: true)
            WidgetRefresh.push(context)
            eventKitSyncCoordinator.refreshNow()

            editingReminder = nil
            editingLink = nil
        }
    }

    // MARK: - Debug Actions

    private func seedThirtyDays() {
        print("DebugHabitToolsSection: seedThirtyDays tapped")
        // Reconnect this to your existing HabitSeeder call if you still want this button.
    }

    private func reloadWidget() {
        WidgetRefresh.push(context)
        eventKitSyncCoordinator.refreshNow()
        print("DebugHabitToolsSection: refreshed widget for habit \(habit.name ?? "Habit")")
    }

    private func refreshReminderTitles() {
        Task { @MainActor in
            await ReminderMetadataRefresher.shared.refreshLinkTitles(in: context)
            HabitCompletionEngine.syncTodayFromReminders(in: context, includeCompleted: true)
            WidgetRefresh.push(context)
            eventKitSyncCoordinator.refreshNow()
            print("DebugHabitToolsSection: manual reminder title refresh tapped")
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

    private func linkStoredStableIdentifier(_ link: HabitReminderLink) -> String? {
        if let id = link.reminderIdentifier, !id.isEmpty {
            return id
        }

        if let id = link.value(forKey: "reminderId") as? String, !id.isEmpty {
            return id
        }

        if let id = link.value(forKey: "reminderID") as? String, !id.isEmpty {
            return id
        }

        return nil
    }

    // MARK: - Delete

    private func deleteLinks(at offsets: IndexSet) {
        let currentLinks = links
        for index in offsets {
            context.delete(currentLinks[index])
        }
        saveContext()
    }

    private func deleteLinkedReminder(_ link: HabitReminderLink) {
        context.delete(link)
        saveContext()
    }

    private func saveContext() {
        do {
            try context.save()
            HabitCompletionEngine.syncTodayFromReminders(in: context, includeCompleted: true)
            WidgetRefresh.push(context)
            eventKitSyncCoordinator.refreshNow()
        } catch {
            print("❌ HabitDetailView: failed saving context: \(error)")
        }
    }
}

#if DEBUG
private struct HabitDetailDebugToolsSection: View {
    let onSeedThirtyDays: () -> Void
    let onReloadWidget: () -> Void
    let onRefreshReminderTitles: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSeedThirtyDays) {
                debugActionRow(
                    title: "Seed 30 Days",
                    subtitle: "Fill recent history for testing",
                    systemImage: "calendar.badge.plus"
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 44)

            Button(action: onReloadWidget) {
                debugActionRow(
                    title: "Reload Widget",
                    subtitle: "Force today widget refresh",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 44)

            Button(action: onRefreshReminderTitles) {
                debugActionRow(
                    title: "Refresh Reminder Titles",
                    subtitle: "Re-pull reminder names from EventKit",
                    systemImage: "text.badge.checkmark"
                )
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func debugActionRow(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
#endif
