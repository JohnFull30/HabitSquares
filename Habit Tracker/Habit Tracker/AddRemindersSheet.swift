import SwiftUI
import EventKit
import CoreData

struct AddRemindersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    let habit: NSManagedObject

    @State private var store = EKEventStore()
    @State private var authDenied = false

    @State private var allReminders: [EKReminder] = []
    @State private var query: String = ""

    // Keys for selection
    @State private var selectedKeys: Set<String> = []
    @State private var alreadyLinkedKeys: Set<String> = []
    @State private var requiredKeys: Set<String> = []

    // Suggested vs All
    @State private var showSuggestedOnly = true

    // MARK: - Stamp format
    // habitsquares://reminder-link/<uuid>
    private let stampScheme = "habitsquares"
    private let stampHost = "reminder-link"

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $showSuggestedOnly) {
                    Text("Suggested").tag(true)
                    Text("All").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                TextField("Search reminders", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                List {
                    ForEach(filteredReminders, id: \.calendarItemIdentifier) { r in
                        reminderRow(r)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Reminders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveLinksAsync()
                            dismiss()
                        }
                    }
                    .disabled(selectedKeys.isEmpty)
                }
            }
            .onAppear {
                Task { await load() }
            }
        }
    }

    // MARK: - Derived

    private var filteredReminders: [EKReminder] {
        let base: [EKReminder] = {
            if showSuggestedOnly {
                // Suggested = due today or within next 7 days OR completed today.
                let now = Date()
                let start = Calendar.current.startOfDay(for: now)
                let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!

                return allReminders.filter { r in
                    if let due = r.dueDateComponents?.date, due >= start && due < end { return true }
                    if r.isCompleted, let cd = r.completionDate, cd >= start && cd < end { return true }
                    return false
                }
            } else {
                return allReminders
            }
        }()

        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return base
        }
        let q = query.lowercased()
        return base.filter { $0.title.lowercased().contains(q) || $0.calendar.title.lowercased().contains(q) }
    }

    // MARK: - UI Row

    private func reminderRow(_ r: EKReminder) -> some View {
        let key = stableIdentifierToStore(for: r)
        let isAlreadyLinked = alreadyLinkedKeys.contains(key)
        let isSelected = selectedKeys.contains(key)

        return Button {
            guard !isAlreadyLinked else { return }
            toggleSelected(key: key)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isAlreadyLinked ? "link" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isAlreadyLinked ? .secondary : (isSelected ? .primary : .secondary))

                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title)
                        .foregroundStyle(isAlreadyLinked ? .secondary : .primary)

                    Text(r.calendar.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected && !isAlreadyLinked {
                    Toggle("Required", isOn: Binding(
                        get: { requiredKeys.contains(key) },
                        set: { newValue in
                            if newValue { requiredKeys.insert(key) }
                            else { requiredKeys.remove(key) }
                        }
                    ))
                    .labelsHidden()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAlreadyLinked)
    }

    private func toggleSelected(key: String) {
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
            requiredKeys.remove(key)
        } else {
            selectedKeys.insert(key)
            // Default: required
            requiredKeys.insert(key)
        }
    }

    // MARK: - Load

    private func load() async {
        let ok = await requestAccessIfNeeded()
        guard ok else {
            authDenied = true
            return
        }

        let reminders = await fetchAllReminders()
        await MainActor.run {
            allReminders = reminders
            hydrateAlreadyLinked()
        }
    }

    private func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .authorized, .fullAccess:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                store.requestFullAccessToReminders { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func fetchAllReminders() async -> [EKReminder] {
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)

        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
    }

    // MARK: - Existing links

    private func hydrateAlreadyLinked() {
        guard let linkEntityName = guessLinkEntityName(in: viewContext),
              let linkToHabitKey = findRelationshipKey(entityName: linkEntityName,
                                                      destinationEntityName: "Habit",
                                                      in: viewContext)
        else {
            alreadyLinkedKeys = []
            return
        }

        let links = fetchLinks(for: habit,
                               linkEntityName: linkEntityName,
                               linkToHabitKey: linkToHabitKey,
                               in: viewContext)

        alreadyLinkedKeys = Set(links.flatMap { link in
            Array(linkStoredKeys(link))
        })
    }

    // MARK: - Save (stamping + Core Data)

    private func saveLinksAsync() async {
        guard let linkEntityName = guessLinkEntityName(in: viewContext) else {
            print("✗ AddRemindersSheet: could not guess link entity name")
            return
        }

        guard let linkToHabitKey = findRelationshipKey(entityName: linkEntityName,
                                                      destinationEntityName: "Habit",
                                                      in: viewContext) else {
            print("✗ AddRemindersSheet: could not find relationship \(linkEntityName) -> Habit")
            return
        }

        // Build map: selectionKey -> EKReminder
        var byKey: [String: EKReminder] = [:]
        for r in allReminders {
            byKey[stableIdentifierToStore(for: r)] = r
        }

        // 1) Ensure each selected reminder has a stamped stable UUID (and save back to EventKit)
        // We batch EventKit saves for speed/consistency.
        var stampedBySelectionKey: [String: String] = [:]

        do {
            for selectionKey in selectedKeys {
                guard !alreadyLinkedKeys.contains(selectionKey) else { continue }
                guard let r = byKey[selectionKey] else { continue }

                let stableUUID = ensureStampedUUID(on: r)
                stampedBySelectionKey[selectionKey] = stableUUID

                // Save reminder (commit later)
                try store.save(r, commit: false)
            }

            // Commit EventKit changes once
            try store.commit()
        } catch {
            // If EventKit save fails, we should not write Core Data links with missing stamps.
            print("✗ AddRemindersSheet: EventKit save/commit failed: \(error)")
            return
        }

        // 2) Write Core Data links using the stamped UUID as the primary identity
        for selectionKey in selectedKeys {
            guard !alreadyLinkedKeys.contains(selectionKey) else { continue }
            guard let r = byKey[selectionKey] else { continue }
            guard let stableUUID = stampedBySelectionKey[selectionKey] else { continue }

            let link = NSEntityDescription.insertNewObject(forEntityName: linkEntityName, into: viewContext)

            // relationship: link -> habit
            link.setIfExistsObject(habit, forKey: linkToHabitKey)

            // Store our stable ID (THIS is what matching should use going forward)
            link.setIfExistsString(stableUUID, forKey: "reminderIdentifier")
            link.setIfExistsString(stableUUID, forKey: "reminderId")
            link.setIfExistsString(stableUUID, forKey: "reminderID")

            // Keep Apple IDs as debug/backstop only (optional but useful)
            link.setIfExistsString(r.calendarItemIdentifier, forKey: "calendarItemIdentifier")
            if let ext = r.calendarItemExternalIdentifier {
                link.setIfExistsString(ext, forKey: "calendarItemExternalIdentifier")
            }

            // metadata
            link.setIfExistsString(r.title, forKey: "title")
            link.setIfExistsString(r.calendar.title, forKey: "calendarTitle")
            link.setIfExistsDate(Date(), forKey: "createdAt")

            // required flag
            let isReq = requiredKeys.contains(selectionKey)
            link.setIfExistsBool(isReq, forKey: "isRequired")
            link.setIfExistsBool(isReq, forKey: "required")

            print("✓ AddRemindersSheet: linked '\(r.title)' with stableUUID=\(stableUUID)")
        }

        do {
            try viewContext.save()
            HabitCompletionEngine.syncTodayFromReminders(in: viewContext, includeCompleted: true)
            print("✓ AddRemindersSheet: saved links + triggered sync")
        } catch {
            print("✗ AddRemindersSheet: Core Data save failed \(error)")
        }
    }

    // MARK: - Stamping helpers

    private func stampedUUID(from reminder: EKReminder) -> String? {
        guard let url = reminder.url else { return nil }
        guard url.scheme?.lowercased() == stampScheme else { return nil }
        guard url.host?.lowercased() == stampHost else { return nil }

        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.isEmpty ? nil : raw
    }

    /// Ensures the reminder has a HabitSquares stable UUID in `reminder.url`.
    /// Returns the stable UUID we should store in Core Data.
    private func ensureStampedUUID(on reminder: EKReminder) -> String {
        if let existing = stampedUUID(from: reminder) {
            return existing
        }

        let uuid = UUID().uuidString
        // habitsquares://reminder-link/<uuid>
        if let url = URL(string: "\(stampScheme)://\(stampHost)/\(uuid)") {
            reminder.url = url
        }
        return uuid
    }

    // MARK: - Link fetch (NO Habit.links)

    private func fetchLinks(for habit: NSManagedObject,
                            linkEntityName: String,
                            linkToHabitKey: String,
                            in context: NSManagedObjectContext) -> [NSManagedObject] {
        let req = NSFetchRequest<NSManagedObject>(entityName: linkEntityName)
        req.predicate = NSPredicate(format: "%K == %@", linkToHabitKey, habit)
        return (try? context.fetch(req)) ?? []
    }

    private func linkStoredKeys(_ link: NSManagedObject) -> Set<String> {
        var keys = Set<String>()
        let candidates = [
            "reminderIdentifier",
            "reminderId",
            "reminderID",
            "calendarItemIdentifier",
            "calendarItemExternalIdentifier"
        ]
        for c in candidates {
            if let s = link.valueIfExists(forKey: c) as? String, !s.isEmpty {
                keys.insert(s)
            }
        }
        return keys
    }

    // MARK: - Stable identifier (for selection UI only)

    /// Selection key for the list UI.
    /// Prefer stamped UUID if present (so the UI stays consistent after stamping),
    /// otherwise fall back to Apple identifiers.
    private func stableIdentifierToStore(for r: EKReminder) -> String {
        if let stamped = stampedUUID(from: r) { return stamped }
        if let ext = r.calendarItemExternalIdentifier, !ext.isEmpty { return ext }
        return r.calendarItemIdentifier
    }

    // MARK: - Model introspection

    private func findRelationshipKey(entityName: String,
                                     destinationEntityName: String,
                                     in context: NSManagedObjectContext) -> String? {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { return nil }
        guard let entity = model.entitiesByName[entityName] else { return nil }

        for (name, rel) in entity.relationshipsByName {
            if rel.destinationEntity?.name == destinationEntityName {
                return name
            }
        }
        return nil
    }

    private func guessLinkEntityName(in context: NSManagedObjectContext) -> String? {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { return nil }

        let common = ["ReminderLink", "ReminderLinkEntity", "HabitReminderLink", "HabitLink", "ReminderLinkModel"]
        for name in common {
            if model.entitiesByName[name] != nil { return name }
        }

        for (name, entity) in model.entitiesByName {
            let attrs = Set(entity.attributesByName.keys)
            let looksLikeLink =
                attrs.contains("reminderIdentifier") ||
                attrs.contains("reminderId") ||
                attrs.contains("calendarItemIdentifier") ||
                attrs.contains("calendarItemExternalIdentifier")

            let hasHabitRel = entity.relationshipsByName.values.contains { $0.destinationEntity?.name == "Habit" }

            if looksLikeLink && hasHabitRel { return name }
        }

        return nil
    }
}

// MARK: - NSManagedObject safe KVC

private extension NSManagedObject {
    func setIfExistsString(_ value: String, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsBool(_ value: Bool, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsDate(_ value: Date, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsObject(_ value: Any?, forKey key: String) {
        guard entity.relationshipsByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func valueIfExists(forKey key: String) -> Any? {
        if entity.attributesByName[key] != nil { return value(forKey: key) }
        if entity.relationshipsByName[key] != nil { return value(forKey: key) }
        return nil
    }
}
