//
//  HabitSquaresSettingsView.swift
//  Habit Tracker
//
//  Created by John Fuller on 5/2/26.
//


import SwiftUI

struct HabitSquaresSettingsView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HabitSquares")
                            .font(.title2.weight(.bold))

                        Text("Track habits with a GitHub-style heatmap powered by your linked Apple Reminders.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("How it works") {
                    Label("Create habits owned by HabitSquares", systemImage: "square.grid.3x3")
                    Label("Link one or more Apple Reminders", systemImage: "checklist")
                    Label("Required reminders decide completion", systemImage: "checkmark.seal")
                    Label("Green means all required reminders were completed that day", systemImage: "calendar.badge.checkmark")
                }

                Section("Reminders") {
                    Text("When a reminder is linked to a habit, HabitSquares checks whether the required reminders were completed for that day. For recurring reminders, completion is based on the reminder completion date, not just the current due date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                if AppFlags.showDevTools {
                    Section("Developer") {
                        Button {
                            hasSeenOnboarding = false
                        } label: {
                            Label("Show Onboarding Again", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                #endif

                Section("Privacy") {
                    Text("HabitSquares uses Apple Reminders permission so you can link reminders to habits. Your habit and reminder-tracking data stays in your app data unless you later enable iCloud/CloudKit syncing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}