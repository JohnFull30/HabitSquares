import SwiftUI
import EventKit
import CoreData

/// Simple debug screen to inspect outstanding Apple Reminders.
/// This is presented from ContentView as a sheet.
struct ReminderListView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var reminders: [EKReminder] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    VStack(spacing: 8) {
                        Text("Error loading reminders")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.red)
                    }
                    .padding()
                } else if isLoading {
                    ProgressView("Loading Reminders…")
                } else if reminders.isEmpty {
                    VStack(spacing: 8) {
                        Text("No outstanding reminders found.")
                            .font(.headline)
                        Text("Check the Xcode console for debug logs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                } else {
                    List(reminders, id: \.calendarItemIdentifier) { reminder in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title)
                                .font(.headline)

                            if let date = reminder.dueDateComponents?.date {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders dDebug")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                loadReminders()
            }
        }
    }

    // MARK: - Debug fetch wrapper
    private func loadReminders() {
        isLoading = true
        errorMessage = nil

        ReminderService.shared.fetchTodayReminders(includeCompleted: true) { fetched in
            Task { @MainActor in
                print("🟢 loadReminders completion, fetched \(fetched.count) total reminders for today")

                // 1) Update the UI list
                self.reminders = fetched

                // 1.5) Ensure CODE reminder is linked to the "Checking" habit (debug only)
                let context = PersistenceController.shared.container.viewContext
                if let codeReminder = fetched.first(where: {
                    $0.title.caseInsensitiveCompare("code") == .orderedSame
                }) {
                    HabitSeeder.ensureCodeReminderLink(
                        in: context,
                        forReminderIdentifier: codeReminder.calendarItemIdentifier
                    )
                }

                // 2) Compute + log habit completion summaries
                HabitCompletionEngine.debugSummaries(in: context, reminders: fetched)

                // 3) Upsert HabitCompletion rows for today for each habit
                HabitCompletionEngine.upsertCompletionsForToday(in: context, reminders: fetched)

                self.isLoading = false
            }
        }
    }
}
