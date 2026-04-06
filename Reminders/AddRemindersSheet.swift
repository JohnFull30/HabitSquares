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
    @State private var linkedToThisHabitStableUUIDs: Set<String> = []
    @State private var linkedAnywhereStableUUIDs: Set<String> = []
    @State private var requiredKeys: Set<String> = []

    // Filters
    private enum FilterMode: String, CaseIterable {
        case suggested = "Suggested"
        case all = "All"
    }

    private enum ReminderLinkPolicy {
        case oneHabitOnly
        case allowMultipleHabits
    }

    private enum ReminderRowState {
        case linkedToThisHabit
        case linkedToAnotherHabit
        case available
    }

    @State private var filterMode: FilterMode = .suggested
    @State private var selectedCalendarID: String? = nil

    // Flip this later if you decide one Apple Reminder can feed multiple habits
    private let reminderLinkPolicy: ReminderLinkPolicy = .oneHabitOnly

    // MARK: - Stamp format
    // habitsquares://reminder-link/<uuid>
    private let stampScheme = "habitsquares"
    private let stampHost = "reminder-link"

    private func handleCreatedReminder(_ r: EKReminder, isRequired: Bool) {
        if !allReminders.contains(where: { $0.calendarItemIdentifier == r.calendarItemIdentifier }) {
            allReminders.append(r)
        }

        selectedCalendarID = r.calendar.calendarIdentifier

        let key = stableIdentifierToStore(for: r)
        selectedKeys.insert(key)

        if isRequired {
            requiredKeys.insert(key)
        } else {
            requiredKeys.remove(key)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                glassHeader

                List {
                    if filteredReminders.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "repeat")
                                .font(.title2)
                                .foregroundStyle(.secondary)

                            Text("No Eligible Reminders")
                                .font(.headline)

                            Text(emptyStateMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    } else {
                        if !linkedFilteredReminders.isEmpty {
                            Section("Already Linked") {
                                ForEach(linkedFilteredReminders, id: \.calendarItemIdentifier) { r in
                                    reminderRow(r)
                                }
                            }
                        }

                        if !blockedFilteredReminders.isEmpty {
                            Section("Linked to Another Habit") {
                                ForEach(blockedFilteredReminders, id: \.calendarItemIdentifier) { r in
                                    reminderRow(r)
                                }
                            }
                        }

                        if !availableFilteredReminders.isEmpty {
                            Section("Available to Link") {
                                ForEach(availableFilteredReminders, id: \.calendarItemIdentifier) { r in
                                    reminderRow(r)
                                }
                            }
                        }
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
            .task {
                await load()
            }
            .sheet(isPresented: $showNewReminderSheet) {
                NewReminderSheet(
                    eventStore: store,
                    habitName: habitName,
                    initialCalendarID: selectedCalendarID
                ) { newReminder, isRequired in
                    handleCreatedReminder(newReminder, isRequired: isRequired)
                }
            }
        }
    }

    // MARK: - Glass header

    private var glassHeader: some View {
        VStack(spacing: 10) {
            if !availableCalendars.isEmpty {
                HStack {
                    Text("List")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        Button("All Lists") {
                            selectedCalendarID = nil
                        }

                        Divider()

                        ForEach(orderedCalendars, id: \.calendarIdentifier) { cal in
                            Button {
                                selectedCalendarID = cal.calendarIdentifier
                            } label: {
                                if selectedCalendarID == cal.calendarIdentifier {
                                    Label(cal.title, systemImage: "checkmark")
                                } else {
                                    Text(cal.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedCalendarTitle)
                                .foregroundStyle(.primary)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
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

    /// HabitSquares eligibility rule for the browser:
    /// - recurring only
    /// - writable reminder list only
    /// - non-empty title
    private var eligibleReminders: [EKReminder] {
        allReminders.filter(isEligibleReminderForHabitBrowser)
    }

    private var availableCalendars: [EKCalendar] {
        let dict = Dictionary(grouping: eligibleReminders, by: { $0.calendar.calendarIdentifier })
        let calendars = dict.values.compactMap { $0.first?.calendar }

        return calendars.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var orderedCalendars: [EKCalendar] {
        let selectedID = selectedCalendarID

        return availableCalendars.sorted { lhs, rhs in
            let lhsIsSelected = lhs.calendarIdentifier == selectedID
            let rhsIsSelected = rhs.calendarIdentifier == selectedID

            if lhsIsSelected != rhsIsSelected {
                return lhsIsSelected
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var selectedCalendarTitle: String {
        guard let selectedCalendarID else { return "All Lists" }

        return availableCalendars.first(where: { $0.calendarIdentifier == selectedCalendarID })?.title
            ?? "All Lists"
    }

    private var emptyStateMessage: String {
        switch filterMode {
        case .suggested:
            return "Only recurring reminders from editable lists are eligible. Try switching to All or choosing another list."
        case .all:
            return "No recurring reminders were found in the current list selection."
        }
    }

    private var filteredReminders: [EKReminder] {
        let base: [EKReminder] = {
            switch filterMode {
            case .suggested:
                let now = Date()
                let start = Calendar.current.startOfDay(for: now)
                let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!

                return eligibleReminders.filter { r in
                    if let due = r.dueDateComponents?.date, due >= start && due < end { return true }
                    if r.isCompleted, let cd = r.completionDate, cd >= start && cd < end { return true }
                    return false
                }

            case .all:
                return eligibleReminders
            }
        }()

        let calendarFiltered: [EKReminder] = {
            guard let id = selectedCalendarID else { return base }
            return base.filter { $0.calendar.calendarIdentifier == id }
        }()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched: [EKReminder] = {
            guard !trimmed.isEmpty else { return calendarFiltered }
            let q = trimmed.lowercased()

            return calendarFiltered.filter {
                $0.title.lowercased().contains(q) ||
                $0.calendar.title.lowercased().contains(q)
            }
        }()

        return dedupeForPickerUI(searched)
    }

    private var linkedFilteredReminders: [EKReminder] {
        filteredReminders.filter { reminder in
            guard let stamp = stampedUUID(from: reminder) else { return false }
            return linkedToThisHabitStableUUIDs.contains(stamp)
        }
    }

    private var blockedFilteredReminders: [EKReminder] {
        guard reminderLinkPolicy == .oneHabitOnly else { return [] }

        return filteredReminders.filter { reminder in
            guard let stamp = stampedUUID(from: reminder) else { return false }
            return linkedAnywhereStableUUIDs.contains(stamp) && !linkedToThisHabitStableUUIDs.contains(stamp)
        }
    }

    private var availableFilteredReminders: [EKReminder] {
        filteredReminders.filter { reminder in
            guard let stamp = stampedUUID(from: reminder) else { return true }

            if linkedToThisHabitStableUUIDs.contains(stamp) {
                return false
            }

            if reminderLinkPolicy == .oneHabitOnly && linkedAnywhereStableUUIDs.contains(stamp) {
                return false
            }

            return true
        }
    }

    private func isEligibleReminderForHabitBrowser(_ reminder: EKReminder) -> Bool {
        let trimmedTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }
        guard reminder.calendar.allowsContentModifications else { return false }
        guard isRecurring(reminder) else { return false }
        return true
    }

    private func isRecurring(_ reminder: EKReminder) -> Bool {
        !(reminder.recurrenceRules?.isEmpty ?? true)
    }

    private func rowState(for reminder: EKReminder) -> ReminderRowState {
        guard let stamp = stampedUUID(from: reminder) else {
            return .available
        }

        if linkedToThisHabitStableUUIDs.contains(stamp) {
            return .linkedToThisHabit
        }

        if reminderLinkPolicy == .oneHabitOnly && linkedAnywhereStableUUIDs.contains(stamp) {
            return .linkedToAnotherHabit
        }

        return .available
    }

    /// Collapse recurring instances / duplicates so the picker is clean.
    private func dedupeForPickerUI(_ reminders: [EKReminder]) -> [EKReminder] {
        let groups = Dictionary(grouping: reminders, by: { pickerIdentity(for: $0) })

        func score(_ r: EKReminder) -> Double {
            let now = Date().timeIntervalSince1970
            let due = r.dueDateComponents?.date?.timeIntervalSince1970 ?? -9e15
            let comp = r.completionDate?.timeIntervalSince1970 ?? -9e15

            let dueScore = (due > 0) ? -abs(due - now) : -9e15
            let compScore = (comp > 0) ? -abs(comp - now) : -9e15
            let completedBump = r.isCompleted ? 1_000_000 : 0

            return max(dueScore, compScore) + Double(completedBump)
        }

        let chosen = groups.values.compactMap { bucket -> EKReminder? in
            bucket.max(by: { score($0) < score($1) })
        }

        return chosen.sorted {
            if $0.calendar.title != $1.calendar.title {
                return $0.calendar.title.localizedCaseInsensitiveCompare($1.calendar.title) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func pickerIdentity(for r: EKReminder) -> String {
        if let stamped = stampedUUID(from: r) { return "stamp:\(stamped)" }
        if let ext = r.calendarItemExternalIdentifier, !ext.isEmpty { return "ext:\(ext)" }
        return "id:\(r.calendarItemIdentifier)"
    }

    // MARK: - UI Row

    private func reminderRow(_ r: EKReminder) -> some View {
        let selectionKey = stableIdentifierToStore(for: r)
        let state = rowState(for: r)
        let isSelected = selectedKeys.contains(selectionKey)

        let isLinkedToThisHabit = state == .linkedToThisHabit
        let isLinkedToAnotherHabit = state == .linkedToAnotherHabit
        let isDisabled = isLinkedToThisHabit || isLinkedToAnotherHabit

        return Button {
            guard !isDisabled else { return }
            toggleSelected(key: selectionKey)
        } label: {
            HStack(spacing: 12) {
                Image(systemName:
                    isLinkedToThisHabit ? "link" :
                    isLinkedToAnotherHabit ? "lock" :
                    (isSelected ? "checkmark.circle.fill" : "circle")
                )
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isDisabled ? .secondary : (isSelected ? .primary : .secondary)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title)
                        .foregroundStyle(isDisabled ? .secondary : .primary)

                    HStack(spacing: 6) {
                        Text(r.calendar.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Repeats")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isLinkedToAnotherHabit {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Used by another habit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isSelected && !isDisabled {
                    Toggle("Required", isOn: Binding(
                        get: { requiredKeys.contains(selectionKey) },
                        set: { newValue in
                            if newValue {
                                requiredKeys.insert(selectionKey)
                            } else {
                                requiredKeys.remove(selectionKey)
                            }
                        }
                    ))
                    .labelsHidden()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func toggleSelected(key: String) {
        if selectedKeys.contains(key) {
            selectedKeys.remove(key)
            requiredKeys.remove(key)
        } else {
            selectedKeys.insert(key)
            requiredKeys.insert(key)
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
                let systemDefaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier

                selectedCalendarID =
                    availableCalendars.first(where: { $0.calendarIdentifier == systemDefaultID })?.calendarIdentifier
                    ?? availableCalendars.first?.calendarIdentifier
            } else if availableCalendars.contains(where: { $0.calendarIdentifier == selectedCalendarID }) == false {
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
              let linkToHabitKey = findRelationshipKey(
                entityName: linkEntityName,
                destinationEntityName: "Habit",
                in: viewContext
              )
        else {
            linkedToThisHabitStableUUIDs = []
            linkedAnywhereStableUUIDs = []
            return
        }

        let allLinksRequest = NSFetchRequest<NSManagedObject>(entityName: linkEntityName)
        let allLinks = (try? viewContext.fetch(allLinksRequest)) ?? []

        linkedAnywhereStableUUIDs = Set(allLinks.flatMap { link in
            Array(linkStoredStableUUIDs(link))
        })

        let linksForThisHabit = fetchLinks(
            for: habit,
            linkEntityName: linkEntityName,
            linkToHabitKey: linkToHabitKey,
            in: viewContext
        )

        linkedToThisHabitStableUUIDs = Set(linksForThisHabit.flatMap { link in
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

        guard let linkToHabitKey = findRelationshipKey(
            entityName: linkEntityName,
            destinationEntityName: "Habit",
            in: viewContext
        ) else {
            print("✗ AddRemindersSheet: could not find relationship \(linkEntityName) -> Habit")
            return
        }

        var byKey: [String: EKReminder] = [:]
        for r in allReminders {
            byKey[stableIdentifierToStore(for: r)] = r
        }

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

        for selectionKey in selectedKeys {
            guard let r = byKey[selectionKey] else { continue }
            guard let stableUUID = stampedBySelectionKey[selectionKey] else { continue }

            let link = NSEntityDescription.insertNewObject(
                forEntityName: linkEntityName,
                into: viewContext
            )

            link.setIfExistsObject(habit, forKey: linkToHabitKey)

            link.setIfExistsString(stableUUID, forKey: "reminderIdentifier")
            link.setIfExistsString(stableUUID, forKey: "reminderId")
            link.setIfExistsString(stableUUID, forKey: "reminderID")

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
            await ReminderMetadataRefresher.shared.refreshLinkTitles(in: viewContext)
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

    private func fetchLinks(
        for habit: NSManagedObject,
        linkEntityName: String,
        linkToHabitKey: String,
        in context: NSManagedObjectContext
    ) -> [NSManagedObject] {
        let req = NSFetchRequest<NSManagedObject>(entityName: linkEntityName)
        req.predicate = NSPredicate(format: "%K == %@", linkToHabitKey, habit)
        return (try? context.fetch(req)) ?? []
    }

    // MARK: - Stable identifier (for selection UI)

    private func stableIdentifierToStore(for r: EKReminder) -> String {
        if let stamped = stampedUUID(from: r) { return stamped }
        if let ext = r.calendarItemExternalIdentifier, !ext.isEmpty { return ext }
        return r.calendarItemIdentifier
    }

    // MARK: - Model introspection

    private func findRelationshipKey(
        entityName: String,
        destinationEntityName: String,
        in context: NSManagedObjectContext
    ) -> String? {
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

        let common = [
            "ReminderLink",
            "ReminderLinkEntity",
            "HabitReminderLink",
            "HabitLink",
            "ReminderLinkModel"
        ]

        for name in common where model.entitiesByName[name] != nil {
            return name
        }

        return model.entities.first(where: { entity in
            entity.name?.localizedCaseInsensitiveContains("link") == true &&
            entity.relationshipsByName.values.contains(where: { $0.destinationEntity?.name == "Habit" })
        })?.name
    }
}

// MARK: - Safe KVC helpers

private extension NSManagedObject {
    func valueIfExists(forKey key: String) -> Any? {
        guard entity.propertiesByName[key] != nil else { return nil }
        return value(forKey: key)
    }

    func setIfExistsString(_ value: String?, forKey key: String) {
        guard entity.propertiesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsBool(_ value: Bool, forKey key: String) {
        guard entity.propertiesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsDate(_ value: Date?, forKey key: String) {
        guard entity.propertiesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsObject(_ value: Any?, forKey key: String) {
        guard entity.propertiesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }
}
