import SwiftUI
import CoreData
import EventKit

struct HabitDetailView: View {
    @ObservedObject var habit: Habit

    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject private var eventKitSyncCoordinator: EventKitSyncCoordinator

    @State private var loadedReminders: [EKReminder] = []
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

            if AppFlags.showDevTools {
                Section(
                    footer:
                        Text("Debug-only actions for seeding, syncing, and widget refresh.")
                        .font(.caption)
                ) {
                    DisclosureGroup {
                        HabitDetailDebugToolsSection(
                            onSeedSelectedDays: { dayCount, pattern in
                                seedSelectedDays(dayCount, pattern: pattern)
                            },
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
                
            }
            }
        .task {
            await loadLinkedReminderCandidates()
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

                Text(linkMetadataText(for: link))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { link.isRequired },
                    set: { newValue in
                        link.isRequired = newValue
                        saveContext()
                    }
                )
            )
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

    private func linkMetadataText(for link: HabitReminderLink) -> String {
        let requirement = link.isRequired ? "Required" : "Optional"

        guard
            let reminder = resolvedReminder(for: link),
            let schedule = reminderScheduleSummary(reminder)
        else {
            return requirement
        }

        return "\(requirement) · \(schedule)"
    }

    private func resolvedReminder(for link: HabitReminderLink) -> EKReminder? {
        guard let storedID = linkStoredStableIdentifier(link) else {
            return nil
        }

        if let direct = reminderStore.calendarItem(withIdentifier: storedID) as? EKReminder {
            return direct
        }

        return loadedReminders.first { reminder in
            if let stamped = stampedUUID(from: reminder), stamped == storedID {
                return true
            }

            if let externalID = reminder.calendarItemExternalIdentifier, externalID == storedID {
                return true
            }

            return reminder.calendarItemIdentifier == storedID
        }
    }

    private func reminderScheduleSummary(_ reminder: EKReminder) -> String? {
        if let recurrence = recurrenceSummary(for: reminder),
           let time = dueTimeSummary(for: reminder) {
            return "\(recurrence) \(time)"
        }

        if let recurrence = recurrenceSummary(for: reminder) {
            return recurrence
        }

        if let time = dueTimeSummary(for: reminder) {
            return time
        }

        return nil
    }

    private func dueTimeSummary(for reminder: EKReminder) -> String? {
        guard let components = reminder.dueDateComponents else { return nil }

        let calendar = Calendar.current

        if let date = calendar.date(from: components) {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }

        if let hour = components.hour, let minute = components.minute {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute

            if let date = calendar.date(from: comps) {
                let formatter = DateFormatter()
                formatter.locale = .current
                formatter.timeStyle = .short
                formatter.dateStyle = .none
                return formatter.string(from: date)
            }
        }

        return nil
    }

    private func recurrenceSummary(for reminder: EKReminder) -> String? {
        guard let rule = reminder.recurrenceRules?.first else { return nil }

        switch rule.frequency {
        case .daily:
            return "Daily"

        case .weekly:
            let days = rule.daysOfTheWeek ?? []
            let weekdayNumbers = days.map(\.dayOfTheWeek.rawValue).sorted()

            if weekdayNumbers == [2, 3, 4, 5, 6] {
                return "Mon–Fri"
            }

            if weekdayNumbers == [1, 7] {
                return "Weekends"
            }

            if weekdayNumbers.count == 7 {
                return "Daily"
            }

            if !weekdayNumbers.isEmpty {
                let symbols = Calendar.current.shortWeekdaySymbols
                let names = weekdayNumbers.map { symbols[$0 - 1] }
                return names.joined(separator: ", ")
            }

            return "Weekly"

        case .monthly:
            return "Monthly"

        case .yearly:
            return "Yearly"

        @unknown default:
            return nil
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
                loadedReminders = reminders
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

    private func seedSelectedDays(_ dayCount: Int, pattern: HabitSeeder.SeedPattern) {
        HabitSeeder.seedCompletions(
            dayCount: dayCount,
            pattern: pattern,
            for: habit,
            in: context,
            markComplete: true
        )
        reloadWidget()
        print("DebugHabitToolsSection: seeded \(dayCount) day(s) with pattern '\(pattern.title)' for \(habit.name ?? "Habit")")
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

    @MainActor
    private func loadLinkedReminderCandidates() async {
        let granted = await requestReminderAccessIfNeeded()
        guard granted else {
            loadedReminders = []
            return
        }

        loadedReminders = await fetchAllRemindersForEditing()
    }

    private func requestReminderAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            return true

        case .writeOnly:
            return false

        case .notDetermined:
            if #available(iOS 17.0, *) {
                do {
                    return try await reminderStore.requestFullAccessToReminders()
                } catch {
                    return false
                }
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
struct HabitDetailDebugToolsSection: View {
    let onSeedSelectedDays: (Int, HabitSeeder.SeedPattern) -> Void
    let onReloadWidget: () -> Void
    let onRefreshReminderTitles: () -> Void

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @State private var seedDayCount: Int = 5
    @State private var seedPattern: HabitSeeder.SeedPattern = .recent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seed Pattern")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Seed Pattern", selection: $seedPattern) {
                        ForEach(HabitSeeder.SeedPattern.allCases) { pattern in
                            Text(pattern.title).tag(pattern)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Seed Days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Seed Days", selection: $seedDayCount) {
                        Text("0").tag(0)
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("7").tag(7)
                        Text("10").tag(10)
                        Text("14").tag(14)
                        Text("21").tag(21)
                        Text("30").tag(30)
                    }
                    .pickerStyle(.menu)
                }

                Button {
                    onSeedSelectedDays(seedDayCount, seedPattern)
                } label: {
                    debugButtonRow(
                        title: "Seed \(seedPattern.title) · \(seedDayCount) Day\(seedDayCount == 1 ? "" : "s")",
                        systemImage: "calendar.badge.plus"
                    )
                }
                .buttonStyle(.plain)

                Button(action: onReloadWidget) {
                    debugButtonRow(
                        title: "Reload Widget",
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)

                Button(action: onRefreshReminderTitles) {
                    debugButtonRow(
                        title: "Refresh Reminder Titles",
                        systemImage: "text.badge.checkmark"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    hasSeenOnboarding = false
                } label: {
                    debugButtonRow(
                        title: "Show Onboarding Again",
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.plain)
            }

            Text("Debug-only actions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func debugButtonRow(
        title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }
}
#endif
