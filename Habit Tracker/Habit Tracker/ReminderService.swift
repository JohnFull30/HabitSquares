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

            // Shared handler so we don't repeat the DispatchQueue.main code
            let handleResult: (Bool, Error?) -> Void = { granted, error in
                DispatchQueue.main.async {
                    print("Reminders: request finished. granted=\(granted), error=\(String(describing: error))")
                    completion(granted)
                }
            }

            if #available(iOS 17.0, *) {
                // New API for iOS 17+
                store.requestFullAccessToReminders { granted, error in
                    handleResult(granted, error)
                }
            } else {
                // Old API for iOS 16 and earlier
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
    /// If access is missing or denied, we just return an empty array.
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

                // 🧪 DEBUG: log each reminder's ID so we can link it to a habit
                for reminder in safe {
                    let title = reminder.title ?? "{no title}"
                    print("""
                    Reminder debug:
                      title = \(title)
                      id = \(reminder.calendarItemIdentifier)
                      completed = \(reminder.isCompleted)
                    """)
                }

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

    /// Fetch **today's** reminders (optionally including completed ones).
    /// This is what we use for the debug summaries so that completed items
    /// still show up in HabitCompletionEngine.
    func fetchTodayReminders(includeCompleted: Bool = true,
                             completion: @escaping ([EKReminder]) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            let calendars = store.calendars(for: .reminder)
            let predicate = store.predicateForReminders(in: calendars)

            store.fetchReminders(matching: predicate) { reminders in
                let all = reminders ?? []

                let startOfDay = Calendar.current.startOfDay(for: Date())
                let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

                let todayReminders = all.filter { reminder in
                    guard let date = reminder.dueDateComponents?.date else { return false }
                    return (startOfDay ... endOfDay).contains(date)
                }

                let finalReminders: [EKReminder]
                if includeCompleted {
                    finalReminders = todayReminders
                } else {
                    finalReminders = todayReminders.filter { !$0.isCompleted }
                }

                DispatchQueue.main.async {
                    print("Reminders (today): fetched \(finalReminders.count) item(s). includeCompleted=\(includeCompleted)")
                    completion(finalReminders)
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
