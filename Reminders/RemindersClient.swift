//
//  Untitled.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/20/25.
//

import Foundation
import Combine
import EventKit

@MainActor
final class RemindersClient: ObservableObject {
    private let store = EKEventStore()

    @Published var reminders: [EKReminder] = []
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    func requestAccess() async -> Bool {
        do {
            let granted = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
                store.requestFullAccessToReminders { granted, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: granted)
                    }
                }
            }

            isAuthorized = granted
            return granted
        } catch {
            errorMessage = error.localizedDescription
            isAuthorized = false
            return false
        }
    }

    func fetchAllReminders() async {
        guard await requestAccess() else { return }
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)

        await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate, completion: { [weak self] items in
                Task { @MainActor in
                    self?.reminders = (items ?? []).sorted { $0.title < $1.title }
                    cont.resume()
                }
            })
        }
    }
}
