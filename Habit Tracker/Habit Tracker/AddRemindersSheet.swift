import SwiftUI
import EventKit
import CoreData

struct AddRemindersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    let habit: NSManagedObject

    @State private var store = EKEventStore()
    
    @State private var showNewReminderSheet = false

    private var habitName: String {
        (habit.value(forKey: "name") as? String) ?? "Habit"
    }

    @State private var allReminders: [EKReminder] = []
    @State private var query: String = ""

    // Keys for selection
    @State private var selectedKeys: Set<String> = []
    @State private var alreadyLinkedStableUUIDs: Set<String> = []
    @State private var requiredKeys: Set<String> = []

    // Filters
    private enum FilterMode: String, CaseIterable {
        case suggested = "Suggested"
        case all = "All"
    }
    @State private var filterMode: FilterMode = .suggested
    @State private var selectedCalendarID: String? = nil

    // MARK: - Stamp format
    // habitsquares://reminder-link/<uuid>
    private let stampScheme = "habitsquares"
    private let stampHost = "reminder-link"

    private func handleCreatedReminder(_ r: EKReminder, isRequired: Bool) {
        // 1) Add it to the current list immediately (no refetch needed)
        if !allReminders.contains(where: { $0.calendarItemIdentifier == r.calendarItemIdentifier }) {
            allReminders.append(r)
        }

        // 2) Optionally jump the list filter to the reminder’s list
        selectedCalendarID = r.calendar.calendarIdentifier

        // 3) Auto-select it so the user can just hit Save
        let key = stableIdentifierToStore(for: r)
        selectedKeys.insert(key)
        if isRequired { requiredKeys.insert(key) }
        else { requiredKeys.remove(key) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                glassHeader

                List {
                    ForEach(filteredReminders, id: \.hsRowID) { r in
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

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filterMode) {
                            ForEach(FilterMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Filter")
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
            .sheet(isPresented: $showNewReminderSheet) {
                NewReminderSheet(habitName: habitName) { newReminder, isRequired in
                    handleCreatedReminder(newReminder, isRequired: isRequired)
                }
            }
            
        }
        
    }

    // MARK: - Glass header

    private var glassHeader: some View {
        VStack(spacing: 10) {
            if !availableCalendars.isEmpty {
                Picker("List", selection: $selectedCalendarID) {
                    Text("All Lists").tag(String?.none)
                    ForEach(availableCalendars, id: \.calendarIdentifier) { cal in
                        Text(cal.title).tag(Optional(cal.calendarIdentifier))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("Search reminders", text: $query)
                .textFieldStyle(.roundedBorder)
            
            Button {
                showNewReminderSheet = true
            } label: {
                Label("New Reminder", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        )
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - Derived

    private var availableCalendars: [EKCalendar] {
        let dict = Dictionary(grouping: allReminders, by: { $0.calendar.calendarIdentifier })
        let calendars = dict.values.compactMap { $0.first?.calendar }
        return calendars.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var filteredReminders: [EKReminder] {
        // 1) Suggested vs All
        let base: [EKReminder] = {
            switch filterMode {
            case .suggested:
                // Suggested = due today or within next 7 days OR completed today
                let now = Date()
                let start = Calendar.current.startOfDay(for: now)
                let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!

                return allReminders.filter { r in
                    if let due = r.dueDateComponents?.date, due >= start && due < end { return true }
                    if r.isCompleted, let cd = r.completionDate, cd >= start && cd < end { return true }
                    return false
                }

            case .all:
                return allReminders
            }
        }()

        // 2) Calendar/List filter
        let calendarFiltered: [EKReminder] = {
            guard let id = selectedCalendarID else { return base }
            return base.filter { $0.calendar.calendarIdentifier == id }
        }()

        // 3) Search filter
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [EKReminder] = {
            guard !trimmed.isEmpty else { return calendarFiltered }
            let q = trimmed.lowercased()
            return calendarFiltered.filter {
                $0.title.lowercased().contains(q) ||
                $0.calendar.title.lowercased().contains(q)
            }
        }()

        // 4) UI dedupe (fix recurring “old instances” clutter)
        return dedupeForPickerUI(searched)
    }

    /// Collapse recurring instances / duplicates so the picker is clean.
    /// We group by our best-known stable identity (stamped UUID if present),
    /// and then pick the “best” representative row.
    private func dedupeForPickerUI(_ reminders: [EKReminder]) -> [EKReminder] {
        let groups = Dictionary(grouping: reminders, by: { pickerIdentity(for: $0) })

        func score(_ r: EKReminder) -> Double {
            // Prefer items that are due soon (future) over far past.
            // Also prefer completed today-ish over ancient completions.
            let now = Date().timeIntervalSince1970
            let due = r.dueDateComponents?.date?.timeIntervalSince1970 ?? -9e15
            let comp = r.completionDate?.timeIntervalSince1970 ?? -9e15

            // If due exists, use closeness to "now" (closer is better).
            let dueScore = (due > 0) ? -abs(due - now) : -9e15
            let compScore = (comp > 0) ? -abs(comp - now) : -9e15

            // Completed items get a slight bump so they don’t disappear in suggested
            let completedBump = r.isCompleted ? 1_000_000 : 0

            return max(dueScore, compScore) + Double(completedBump)
        }

        let chosen = groups.values.compactMap { bucket -> EKReminder? in
            bucket.max(by: { score($0) < score($1) })
        }

        // Make it stable + nice to scan (calendar then title)
        return chosen.sorted {
            if $0.calendar.title != $1.calendar.title {
                return $0.calendar.title.localizedCaseInsensitiveCompare($1.calendar.title) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func pickerIdentity(for r: EKReminder) -> String {
        // For the picker list, this is the “identity” of a reminder across recurring instances.
        // Prefer our stamp if present; otherwise fall back to Apple ids.
        if let stamped = stampedUUID(from: r) { return "stamp:\(stamped)" }
        if let ext = r.calendarItemExternalIdentifier, !ext.isEmpty { return "ext:\(ext)" }
        return "id:\(r.calendarItemIdentifier)"
    }

    // MARK: - UI Row

    private func reminderRow(_ r: EKReminder) -> some View {
        let selectionKey = stableIdentifierToStore(for: r)

        // IMPORTANT: Only consider as "already linked" if the reminder itself has a stamp
        // AND we have that same stamp saved in Core Data.
        let stamp = stampedUUID(from: r)
        let isAlreadyLinked = (stamp != nil) && alreadyLinkedStableUUIDs.contains(stamp!)
        let isSelected = selectedKeys.contains(selectionKey)

        return Button {
            guard !isAlreadyLinked else { return }
            toggleSelected(key: selectionKey)
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
                        get: { requiredKeys.contains(selectionKey) },
                        set: { newValue in
                            if newValue { requiredKeys.insert(selectionKey) }
                            else { requiredKeys.remove(selectionKey) }
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
            requiredKeys.insert(key) // default required
        }
    }

    // MARK: - Load

    private func load() async {
        let ok = await requestAccessIfNeeded()
        guard ok else { return }

        let reminders = await fetchAllReminders()
        await MainActor.run {
            allReminders = reminders
            hydrateAlreadyLinked()

            if selectedCalendarID == nil {
                selectedCalendarID = availableCalendars.first?.calendarIdentifier
            }
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
            alreadyLinkedStableUUIDs = []
            return
        }

        let links = fetchLinks(for: habit,
                               linkEntityName: linkEntityName,
                               linkToHabitKey: linkToHabitKey,
                               in: viewContext)

        // ✅ ONLY read our stable UUID fields (not legacy Apple IDs).
        alreadyLinkedStableUUIDs = Set(links.flatMap { link in
            Array(linkStoredStableUUIDs(link))
        })
    }

    private func linkStoredStableUUIDs(_ link: NSManagedObject) -> Set<String> {
        var keys = Set<String>()
        let candidates = ["reminderIdentifier", "reminderId", "reminderID"]
        for c in candidates {
            if let s = link.valueIfExists(forKey: c) as? String, !s.isEmpty {
                keys.insert(s)
            }
        }
        return keys
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

        // 1) Ensure each selected reminder has a stamped stable UUID (save back to EventKit)
        var stampedBySelectionKey: [String: String] = [:]

        do {
            for selectionKey in selectedKeys {
                guard let r = byKey[selectionKey] else { continue }

                let stableUUID = ensureStampedUUID(on: r)
                stampedBySelectionKey[selectionKey] = stableUUID

                try store.save(r, commit: false)
            }
            try store.commit()
        } catch {
            print("✗ AddRemindersSheet: EventKit save/commit failed: \(error)")
            return
        }

        // 2) Write Core Data links using stamped UUID
        for selectionKey in selectedKeys {
            guard let r = byKey[selectionKey] else { continue }
            guard let stableUUID = stampedBySelectionKey[selectionKey] else { continue }

            let link = NSEntityDescription.insertNewObject(forEntityName: linkEntityName, into: viewContext)

            link.setIfExistsObject(habit, forKey: linkToHabitKey)

            link.setIfExistsString(stableUUID, forKey: "reminderIdentifier")
            link.setIfExistsString(stableUUID, forKey: "reminderId")
            link.setIfExistsString(stableUUID, forKey: "reminderID")

            // keep debug/backstop only
            link.setIfExistsString(r.calendarItemIdentifier, forKey: "calendarItemIdentifier")
            if let ext = r.calendarItemExternalIdentifier {
                link.setIfExistsString(ext, forKey: "calendarItemExternalIdentifier")
            }

            link.setIfExistsString(r.title, forKey: "title")
            link.setIfExistsString(r.calendar.title, forKey: "calendarTitle")
            link.setIfExistsDate(Date(), forKey: "createdAt")

            let isReq = requiredKeys.contains(selectionKey)
            link.setIfExistsBool(isReq, forKey: "isRequired")
            link.setIfExistsBool(isReq, forKey: "required")
        }

        do {
            try viewContext.save()
            HabitCompletionEngine.syncTodayFromReminders(in: viewContext, includeCompleted: true)
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

    private func ensureStampedUUID(on reminder: EKReminder) -> String {
        if let existing = stampedUUID(from: reminder) { return existing }

        let uuid = UUID().uuidString
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

    // MARK: - Stable identifier (for selection UI)

    private func stableIdentifierToStore(for r: EKReminder) -> String {
        // For selection/UI: prefer stamp if present so the row stays consistent after stamping.
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

// MARK: - SwiftUI List identity helper

private extension EKReminder {
    var hsRowID: String {
        let due = dueDateComponents?.date?.timeIntervalSince1970 ?? -1
        let comp = completionDate?.timeIntervalSince1970 ?? -1

        let base = (calendarItemExternalIdentifier?.isEmpty == false)
            ? calendarItemExternalIdentifier!
            : calendarItemIdentifier

        return [
            base,
            calendar.title,
            title,
            String(due),
            String(isCompleted),
            String(comp)
        ].joined(separator: "|")
    }
}
