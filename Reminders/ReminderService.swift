import Foundation
import EventKit
import CoreData

/// Central place for talking to EventKit Reminders.
final class ReminderService {

    static let shared = ReminderService()
    private let store = EKEventStore()

    private init() {}

    // MARK: - Authorization

    func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            print("Reminders: access already authorized.")
            completion(true)

        case .notDetermined:
            print("Reminders: status is notDetermined, requesting access...")

            let handleResult: (Bool, Error?) -> Void = { granted, error in
                DispatchQueue.main.async {
                    print("Reminders: request finished. granted=\(granted), error=\(String(describing: error))")
                    completion(granted)
                }
            }

            if #available(iOS 17.0, *) {
                store.requestFullAccessToReminders { granted, error in
                    handleResult(granted, error)
                }
            } else {
                store.requestAccess(to: .reminder) { granted, error in
                    handleResult(granted, error)
                }
            }

        case .writeOnly, .denied, .restricted:
            print("Reminders: access denied/restricted/write-only.")
            completion(false)

        @unknown default:
            print("Reminders: unknown authorization status: \(status)")
            completion(false)
        }
    }

    // MARK: - Date helpers

    private func dayWindow(for date: Date, cal: Calendar = .current) -> (start: Date, end: Date) {
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    private func isInDay(_ d: Date?, day: Date, cal: Calendar = .current) -> Bool {
        guard let d else { return false }
        return cal.isDate(d, inSameDayAs: day)
    }

    // MARK: - Stable ID helpers (read-only here; we’ll write stamps in Step 2)

    /// If we stamped a stable UUID into the reminder’s URL, read it back.
    /// Expected format: habitsquares://reminder-link/<uuid>
    func stampedStableID(from reminder: EKReminder) -> String? {
        guard let url = reminder.url else { return nil }
        guard url.scheme?.lowercased() == "habitsquares" else { return nil }
        guard url.host?.lowercased() == "reminder-link" else { return nil }

        // path is like "/<uuid>"
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.isEmpty ? nil : raw
    }

    /// Best-effort stable identifier (read-only).
    /// Priority: stamped UUID -> external identifier -> calendar item identifier
    func bestStableIdentifier(for reminder: EKReminder) -> String {
        if let stamped = stampedStableID(from: reminder) {
            return "stamp:\(stamped)"
        }
        if let ext = reminder.calendarItemExternalIdentifier, !ext.isEmpty {
            return "ext:\(ext)"
        }
        return "id:\(reminder.calendarItemIdentifier)"
    }

    // MARK: - Fetching

    /// Fetch all **incomplete** reminders.
    func fetchOutstandingReminders(completion: @escaping ([EKReminder]) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            let calendars = store.calendars(for: .reminder)
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars
            )

            store.fetchReminders(matching: predicate) { reminders in
                let safe = reminders ?? []
                DispatchQueue.main.async {
                    print("Reminders: fetched \(safe.count) outstanding item(s).")
                    completion(safe)
                }
            }

        case .writeOnly, .denied, .restricted:
            print("Reminders: access denied/restricted/write-only.")
            completion([])

        case .notDetermined:
            print("Reminders: status notDetermined in fetchOutstandingReminders – call requestAccessIfNeeded first.")
            completion([])

        @unknown default:
            print("Reminders: unknown authorization status: \(status)")
            completion([])
        }
    }

    /// Fetch reminders that are **due today** (optimized: uses date-range predicates).
    /// If `includeCompleted=true`, you get:
    ///  - incomplete reminders due today
    ///  - completed reminders completed today *that are also due today*
    /// If `includeCompleted=false`, you get only incomplete due-today items.
    func fetchTodayReminders(
        includeCompleted: Bool = true,
        completion: @escaping ([EKReminder]) -> Void
    ) {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            let calendars = store.calendars(for: .reminder)
            let today = Date()
            let window = dayWindow(for: today)

            // 1) Incomplete due today
            let incompletePredicate = store.predicateForIncompleteReminders(
                withDueDateStarting: window.start,
                ending: window.end,
                calendars: calendars
            )

            store.fetchReminders(matching: incompletePredicate) { [weak self] incomplete in
                guard let self else { return }

                let incomplete = incomplete ?? []

                // If we don’t want completed, finish here.
                if includeCompleted == false {
                    DispatchQueue.main.async {
                        self.debugDump(reminders: incomplete, label: "DueToday (incomplete only)", day: today)
                        completion(incomplete)
                    }
                    return
                }

                // 2) Completed today (then filter to due today to match your original “due today” semantics)
                let completedPredicate = self.store.predicateForCompletedReminders(
                    withCompletionDateStarting: window.start,
                    ending: window.end,
                    calendars: calendars
                )

                self.store.fetchReminders(matching: completedPredicate) { completed in
                    let completed = (completed ?? []).filter { r in
                        // Keep only those that are due today (same as your old behavior)
                        self.isInDay(r.dueDateComponents?.date, day: today)
                    }

                    // Merge + de-dupe
                    var seen = Set<String>()
                    var merged: [EKReminder] = []

                    func add(_ r: EKReminder) {
                        let key = self.bestStableIdentifier(for: r) + "|" + (r.dueDateComponents?.date.map { "\($0.timeIntervalSince1970)" } ?? "noDue")
                        if seen.insert(key).inserted {
                            merged.append(r)
                        }
                    }

                    incomplete.forEach(add)
                    completed.forEach(add)

                    DispatchQueue.main.async {
                        self.debugDump(reminders: merged, label: "DueToday (incomplete + completed)", day: today)
                        completion(merged)
                    }
                }
            }

        case .writeOnly, .denied, .restricted:
            print("Reminders: access denied/restricted/write-only in fetchTodayReminders.")
            completion([])

        case .notDetermined:
            print("Reminders: status notDetermined in fetchTodayReminders – call requestAccessIfNeeded first.")
            completion([])

        @unknown default:
            print("Reminders: unknown authorization status in fetchTodayReminders: \(status)")
            completion([])
        }
    }

    // MARK: - Debug

    private func debugDump(reminders: [EKReminder], label: String, day: Date) {
        print("Reminders \(label): fetched \(reminders.count) item(s) for day=\(day).")


        
    }
}

// Linking is local-only: never rewrite a reminder's URL, notes, dates or recurrence.
// Existing URL stamps remain readable for links made by earlier versions.
enum ReminderLinkIdentity {
    static func stamp(in reminder: EKReminder) -> String? {
        guard let url = reminder.url,
              url.scheme?.lowercased() == "habitsquares",
              url.host?.lowercased() == "reminder-link" else { return nil }
        let value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value.isEmpty ? nil : value
    }

    static func identifier(for reminder: EKReminder) -> String {
        if let stamp = stamp(in: reminder) { return stamp }
        if let external = reminder.calendarItemExternalIdentifier, !external.isEmpty { return external }
        return reminder.calendarItemIdentifier
    }

    static func normalized(_ key: String) -> String {
        for prefix in ["stamp:", "ext:", "id:"] where key.hasPrefix(prefix) {
            return String(key.dropFirst(prefix.count))
        }
        return key
    }

    static func keys(for reminder: EKReminder) -> Set<String> {
        var values = [reminder.calendarItemIdentifier]
        if let external = reminder.calendarItemExternalIdentifier { values.append(external) }
        if let stamp = stamp(in: reminder) { values.append(stamp) }
        return Set(values.filter { !$0.isEmpty })
    }

    static func storedKeys(_ link: NSManagedObject) -> Set<String> {
        let names = ["reminderIdentifier", "reminderKey", "ekReminderID", "reminderId", "reminderID",
                     "stampedUUID", "stampUUID", "stamp", "reminderExternalIdentifier",
                     "calendarItemExternalIdentifier", "calendarItemIdentifier"]
        return Set(names.compactMap { name in
            guard link.entity.attributesByName[name] != nil,
                  let value = link.value(forKey: name) as? String, !value.isEmpty else { return nil }
            return normalized(value)
        })
    }

    static func matches(_ reminder: EKReminder, link: NSManagedObject) -> Bool {
        !storedKeys(link).isDisjoint(with: keys(for: reminder))
    }

    static func populate(_ link: NSManagedObject, from reminder: EKReminder, required: Bool) {
        // Use the existing model attributes; no schema or EventKit writes.
        let values: [String: Any] = [
            "id": UUID(), "reminderIdentifier": identifier(for: reminder),
            "reminderKey": identifier(for: reminder), "ekReminderID": reminder.calendarItemIdentifier,
            "title": reminder.title ?? "", "isRequired": required
        ]
        for (key, value) in values where link.entity.attributesByName[key] != nil {
            link.setValue(value, forKey: key)
        }
    }
}

@MainActor
enum ReminderLinker {
    enum LinkError: Error { case missingIdentifier }

    static func save(_ reminders: [EKReminder], requiredKeys: Set<String>, habit: NSManagedObject,
                     in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HabitReminderLink")
        let existing = try context.fetch(request)
        var linkedKeys = Set(existing.flatMap { ReminderLinkIdentity.storedKeys($0) })
        var inserted: [NSManagedObject] = []
        do {
            for reminder in reminders {
                let keys = ReminderLinkIdentity.keys(for: reminder)
                guard !keys.isEmpty else { throw LinkError.missingIdentifier }
                // Recheck the existing one-habit policy at save time, including legacy links.
                guard linkedKeys.isDisjoint(with: keys) else { continue }
                let link = NSEntityDescription.insertNewObject(forEntityName: "HabitReminderLink", into: context)
                inserted.append(link)
                link.setValue(habit, forKey: "habit")
                ReminderLinkIdentity.populate(link, from: reminder,
                    required: requiredKeys.contains(ReminderLinkIdentity.identifier(for: reminder)))
                linkedKeys.formUnion(keys)
            }
            try context.save()
        } catch {
            // Only discard this failed attempt's unsaved insertions, never other pending edits.
            for link in inserted where link.isInserted { context.delete(link) }
            throw error
        }
    }
}
