//
//  ReminderAccessCoordinator.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/24/26.
//


import Foundation
import EventKit
import Combine

@MainActor
final class ReminderAccessCoordinator: ObservableObject {
    @Published private(set) var accessState: ReminderAccessState = .unknown

    private let eventStore = EKEventStore()

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .fullAccess:
            accessState = .authorized
        case .denied, .restricted:
            accessState = .denied
        case .notDetermined, .writeOnly:
            accessState = .unknown
        @unknown default:
            accessState = .unknown
        }
    }

    func requestAccess() async {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            accessState = granted ? .authorized : .denied
        } catch {
            accessState = .denied
        }
    }
}
