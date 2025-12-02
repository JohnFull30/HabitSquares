import Foundation
import EventKit

final class ReminderService {
    static let shared = ReminderService()

    private let store = EKEventStore()

    private init() {}

    // MARK: - Access

    func requestAccessIfNeeded(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            store.requestFullAccessToReminders { granted, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❗️Reminders access error:", error)
                    }
                    print("Reminders access granted? \(granted)")
                    completion(granted)
                }
            }
        } else {
            store.requestAccess(to: .reminder) { granted, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❗️Reminders access error:", error)
                    }
                    print("Reminders access granted? \(granted)")
                    completion(granted)
                }
            }
        }
    }

    // MARK: - Fetch

    func fetchOutstandingReminders(completion: @escaping ([EKReminder]) -> Void) {
        requestAccessIfNeeded { granted in
            guard granted else {
                print("❗️No reminder access – returning empty list.")
                completion([])
                return
            }

            let predicate = self.store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )

            self.store.fetchReminders(matching: predicate) { reminders in
                DispatchQueue.main.async {
                    let result = reminders ?? []
                    print("📌 Fetched \(result.count) outstanding reminders")
                    completion(result)
                }
            }
        }
    }
}
