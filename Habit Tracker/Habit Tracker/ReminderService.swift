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
                print("Reminders: fetched \(safe.count) item(s).")
                completion(safe)
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

    /// Fetch reminders that are **due today**.
    /// If `includeCompleted=true`, you get both completed + incomplete due-today items.
    /// If `includeCompleted=false`, you get only incomplete due-today items.
    func fetchTodayReminders(
        includeCompleted: Bool = true,
        completion: @escaping ([EKReminder]) -> Void
    ) {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            let calendars = store.calendars(for: .reminder)
            let predicate = store.predicateForReminders(in: calendars)

            store.fetchReminders(matching: predicate) { reminders in
                let all = reminders ?? []

                let today = Date()

                let todayReminders = all.filter { r in
                    guard let due = r.dueDateComponents?.date else { return false }
                    guard Calendar.current.isDate(due, inSameDayAs: today) else { return false }

                    // includeCompleted means: include completed reminders that are due today
                    return includeCompleted ? true : !r.isCompleted
                }

                DispatchQueue.main.async {
                    print("Reminders (due today): fetched \(todayReminders.count) item(s). includeCompleted=\(includeCompleted)")

                    for r in todayReminders {
                        print("""
                        DueToday debug:
                          title=\(r.title ?? "<no title>")
                          due=\(String(describing: r.dueDateComponents?.date))
                          isCompleted=\(r.isCompleted)
                          completionDate=\(String(describing: r.completionDate))
                          id=\(r.calendarItemIdentifier)
                        """)
                    }

                    completion(todayReminders)
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
} 
