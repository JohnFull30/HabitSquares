//
//  EventKitSyncCoordinator.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/5/26.
//


import Foundation
import EventKit
import Combine

@MainActor
final class EventKitSyncCoordinator: ObservableObject {
    let eventStore: EKEventStore

    /// Bump this when reminder/calendar data changes so views can react.
    @Published private(set) var refreshTick: Int = 0

    private var hasStartedObserving = false
    private var pendingRefreshTask: Task<Void, Never>?

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func startObserving() {
        guard !hasStartedObserving else { return }
        hasStartedObserving = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEventStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }

    func stopObserving() {
        NotificationCenter.default.removeObserver(
            self,
            name: .EKEventStoreChanged,
            object: eventStore
        )

        hasStartedObserving = false
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
    }

    func refreshNow() {
        pendingRefreshTask?.cancel()
        refreshTick &+= 1
    }

    @objc
    private func handleEventStoreChanged() {
        scheduleDebouncedRefresh()
    }

    private func scheduleDebouncedRefresh() {
        pendingRefreshTask?.cancel()

        pendingRefreshTask = Task { @MainActor in
            // Small debounce so repeated EventKit notifications
            // don’t cause a burst of refreshes.
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else { return }
            refreshTick &+= 1
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pendingRefreshTask?.cancel()
    }
}