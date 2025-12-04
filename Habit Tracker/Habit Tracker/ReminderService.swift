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

                DispatchQueue.main.async {
                    completion(safe)
                }
            }

        case .writeOnly, .denied, .restricted:
            print("Reminders: access denied/restricted/write-only in fetchOutstandingReminders.")
            DispatchQueue.main.async {
                completion([]) // no data, but not an error
            }

        case .notDetermined:
            print("Reminders: status notDetermined in fetchOutstandingReminders – call requestAccessIfNeeded first.")
            DispatchQueue.main.async {
                completion([])
            }

        @unknown default:
            print("Reminders: unknown authorization status in fetchOutstandingReminders: \(status)")
            DispatchQueue.main.async {
                completion([])
            }
        }
    }
}
