import Foundation
import EventKit

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

        for r in reminders {
            let due = r.dueDateComponents?.date
            let stamped = stampedStableID(from: r) ?? "<none>"
            let ext = r.calendarItemExternalIdentifier ?? "<nil>"
            let id = r.calendarItemIdentifier

            print("""
            Reminder debug:
              title=\(r.title ?? "<no title>")
              due=\(String(describing: due))
              isCompleted=\(r.isCompleted)
              completionDate=\(String(describing: r.completionDate))
              stampedStableID=\(stamped)
              externalID=\(ext)
              itemID=\(id)
              url=\(String(describing: r.url))
            """)
        }
    }
}
