//
//  HowItWorksView.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/24/26.
//


import SwiftUI

struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("How HabitSquares works") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Habits are created in HabitSquares.")
                        Text("You can optionally link one or more Apple Reminders to each habit.")
                        Text("A day turns green only when all required linked reminders are completed for that day.")
                    }
                    .padding(.vertical, 4)
                }

                Section("Common questions") {
                    VStack(alignment: .leading, spacing: 12) {
                        helpRow(
                            title: "Why isn’t this square green?",
                            body: "A square turns green only when all required reminders linked to that habit are completed for that day."
                        )

                        helpRow(
                            title: "Do I need Apple Reminders?",
                            body: "No. HabitSquares owns your habits. Reminders are optional links that can help update a habit automatically."
                        )

                        helpRow(
                            title: "Can one habit have multiple reminders?",
                            body: "Yes. A habit can link to multiple reminders, and only the reminders marked as required count toward green completion."
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func helpRow(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}