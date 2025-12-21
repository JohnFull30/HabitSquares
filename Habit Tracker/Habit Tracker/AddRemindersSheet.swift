import SwiftUI
import CoreData
import EventKit

struct AddRemindersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    let habit: Habit

    // EventKit
    private let store = EKEventStore()

    // UI state
    @State private var isLoading = true
    @State private var authDenied = false

    @State private var allReminders: [EKReminder] = []
    @State private var allCalendars: [EKCalendar] = []
    @State private var selectedCalendar: EKCalendar? = nil

    @State private var query = ""
    @State private var mode: PickerMode = .suggested

    // Core Data state
    @State private var alreadyLinkedKeys = Set<String>()   // stable “key” we store for comparisons
    @State private var selectedKeys = Set<String>()        // what user is selecting right now

    enum PickerMode: String, CaseIterable, Identifiable {
        case suggested = "Suggested"
        case all = "All"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if authDenied {
                    ContentUnavailableView(
                        "Reminders Access Needed",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Enable Reminders access in Settings to link reminders to a habit.")
                    )
                    .padding()
                } else if isLoading {
                    ProgressView("Loading reminders…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        headerControls

                        List {
                            ForEach(filteredReminders, id: \.calendarItemIdentifier) { r in
                                reminderRow(r)
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("Add Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLinks()
                        dismiss()
                    }
                    .disabled(selectedKeys.isEmpty || selectedKeys.subtracting(alreadyLinkedKeys).isEmpty)
                }
            }
            .task {
                await loadEverything()
            }
        }
    }

    // MARK: - Header controls

    private var headerControls: some View {
        VStack(spacing: 10) {
            // List filter
            HStack {
                Text("List")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button {
                        selectedCalendar = nil
                    } label: {
                        Label("All Lists", systemImage: selectedCalendar == nil ? "checkmark" : "")
                    }

                    Divider()

                    ForEach(allCalendars, id: \.calendarIdentifier) { cal in
                        Button {
                            selectedCalendar = cal
                        } label: {
                            HStack {
                                Text(cal.title)
                                Spacer()
                                if selectedCalendar?.calendarIdentifier == cal.calendarIdentifier {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedCalendar?.title ?? "All Lists")
                        Image(systemName: "chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Suggested / All toggle
            Picker("", selection: $mode) {
                ForEach(PickerMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            // Search
            TextField("Search reminders", text: $query)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Filtered reminders

    private var filteredReminders: [EKReminder] {
        var base = allReminders

        // calendar filter
        if let selectedCalendar {
            base = base.filter { $0.calendar.calendarIdentifier == selectedCalendar.calendarIdentifier }
        }
        
        // Hide completed reminders by default (unless already linked/selected)
        base = base.filter { r in
            let key = reminderStableKey(r)
            return (!r.isCompleted) || alreadyLinkedKeys.contains(key) || selectedKeys.contains(key)
        }

        // Suggested mode:
        // - due today OR completed today OR recurring
        // - PLUS always include anything already linked/selected so it doesn’t “disappear”
        if mode == .suggested {
            base = base.filter { r in
                let key = reminderStableKey(r)
                return isSuggested(r) || alreadyLinkedKeys.contains(key) || selectedKeys.contains(key)
            }
        }

        // search
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            base = base.filter { $0.title.lowercased().contains(q) }
        }

        // sort: incomplete first, then title
        return base.sorted {
            if $0.isCompleted != $1.isCompleted { return $0.isCompleted == false }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func isSuggested(_ r: EKReminder) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        func isInToday(_ d: Date) -> Bool { d >= today && d < tomorrow }

        if let due = r.dueDateComponents?.date, isInToday(due) { return true }
        if r.isCompleted, let cd = r.completionDate, isInToday(cd) { return true }
        if let rules = r.recurrenceRules, !rules.isEmpty { return true }

        return false
    }

    // MARK: - Row

    @ViewBuilder
    private func reminderRow(_ r: EKReminder) -> some View {
        let key = reminderStableKey(r)
        let isChecked = selectedKeys.contains(key) || alreadyLinkedKeys.contains(key)
        let isLocked = alreadyLinkedKeys.contains(key)

        Button {
            guard !isLocked else { return }
            if selectedKeys.contains(key) {
                selectedKeys.remove(key)
            } else {
                selectedKeys.insert(key)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title)
                        .foregroundStyle(.primary)

                    Text(r.calendar.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(isLocked ? "Linked" : "Required")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load

    @MainActor
    private func loadEverything() async {
        isLoading = true
        authDenied = false

        await requestAccessIfNeeded()
        guard !authDenied else {
            isLoading = false
            return
        }

        allCalendars = store.calendars(for: .reminder)
        alreadyLinkedKeys = fetchAlreadyLinkedKeys(for: habit)
        allReminders = await fetchAllReminders()

        isLoading = false
    }

    @MainActor
    private func requestAccessIfNeeded() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            authDenied = false

        case .notDetermined:
            do {
                try await store.requestFullAccessToReminders()
                authDenied = false
            } catch {
                authDenied = true
            }

        default:
            authDenied = true
        }
    }

    private func fetchAllReminders() async -> [EKReminder] {
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    // MARK: - Save links

    @MainActor
    private func saveLinks() {
        let newKeys = selectedKeys.subtracting(alreadyLinkedKeys)
        guard !newKeys.isEmpty else { return }

        let byKey: [String: EKReminder] = Dictionary(
            uniqueKeysWithValues: allReminders.map { (reminderStableKey($0), $0) }
        )

        for key in newKeys {
            guard let r = byKey[key] else { continue }

            let link = NSEntityDescription.insertNewObject(
                forEntityName: "HabitReminderLink",
                into: viewContext
            )

            // relationship to habit (try common key names)
            if link.entity.relationshipsByName["habit"] != nil {
                link.setValue(habit, forKey: "habit")
            } else if link.entity.relationshipsByName["parentHabit"] != nil {
                link.setValue(habit, forKey: "parentHabit")
            } else if link.entity.relationshipsByName["ownerHabit"] != nil {
                link.setValue(habit, forKey: "ownerHabit")
            }

            let stableID = stableIdentifierToStore(for: r)

            // store identifiers defensively (only if the attribute exists)
            link.setIfExists(stableID, forKey: "id")
            link.setIfExists(stableID, forKey: "reminderID")
            link.setIfExists(stableID, forKey: "reminderId")

            link.setIfExists(r.title, forKey: "title")
            link.setIfExists(r.calendar.title, forKey: "calendarTitle")

            // default: required
            link.setIfExists(true, forKey: "isRequired")
            link.setIfExists(true, forKey: "required")

            link.setIfExists(Date(), forKey: "createdAt")
        }

        do {
            try viewContext.save()
        } catch {
            print("❌ AddRemindersSheet: failed saving links: \(error)")
        }
    }

    // MARK: - Already linked keys (CRASH-PROOF)

    private func fetchAlreadyLinkedKeys(for habit: Habit) -> Set<String> {
        let req = NSFetchRequest<NSManagedObject>(entityName: "HabitReminderLink")

        do {
            let links = try viewContext.fetch(req)

            // keep only links that belong to THIS habit, without guessing relationship names
            let linksForHabit: [NSManagedObject] = links.filter { link in
                if let h = link.valueIfExists(forKey: "habit") as? Habit, h.objectID == habit.objectID { return true }
                if let h = link.valueIfExists(forKey: "parentHabit") as? Habit, h.objectID == habit.objectID { return true }
                if let h = link.valueIfExists(forKey: "ownerHabit") as? Habit, h.objectID == habit.objectID { return true }
                return false
            }

            // read whatever id fields actually exist in your model (NO crashes)
            let ids: [String] = linksForHabit.compactMap { link in
                if let s = link.valueIfExists(forKey: "id") as? String { return s }
                if let s = link.valueIfExists(forKey: "reminderID") as? String { return s }
                if let s = link.valueIfExists(forKey: "reminderId") as? String { return s }
                return nil
            }

            return Set(ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        } catch {
            print("❌ AddRemindersSheet: failed fetching existing links: \(error)")
            return []
        }
    }

    // MARK: - Reminder stable key

    private func reminderStableKey(_ r: EKReminder) -> String {
        let raw = stableIdentifierToStore(for: r)
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func stableIdentifierToStore(for r: EKReminder) -> String {
        if let ext = r.calendarItemExternalIdentifier, !ext.isEmpty { return ext }
        return r.calendarItemIdentifier
    }
}

// MARK: - NSManagedObject safe helpers
private extension NSManagedObject {
    func setIfExists(_ value: Any?, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func valueIfExists(forKey key: String) -> Any? {
        guard entity.attributesByName[key] != nil || entity.relationshipsByName[key] != nil else { return nil }
        return value(forKey: key)
    }
}
