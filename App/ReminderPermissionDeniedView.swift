//
//  ReminderPermissionDeniedView.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/24/26.
//


import SwiftUI

struct ReminderPermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.slash")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Reminders Access Needed")
                .font(.title3.bold())

            Text("To link Apple Reminders to a habit, allow Reminders access in Settings. HabitSquares can still work without it, but linked reminders won’t update your squares automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}