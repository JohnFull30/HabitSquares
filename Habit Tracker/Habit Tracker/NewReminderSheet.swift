//
//  NewReminderSheet.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/23/25.
//


import SwiftUI
import EventKit

/// Simple “v1” creator:
/// - Creates a DAILY repeating reminder in a selected Reminders list (calendar)
/// - Optionally sets a due time
/// - Returns the created EKReminder so the caller can link it to the Habit
struct NewReminderSheet: View {
    let habitName: String
    let onCreated: (EKReminder, Bool) -> Void   // (reminder, isRequired)

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var isRequired: Bool = true

    @State private var calendars: [EKCalendar] = []
    @State private var selectedCalendar: EKCalendar?

    @State private var hasDueTime: Bool = false
    @State private var dueTime: Date = .now

    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    private let store = EKEventStore()

    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)

                    Toggle("Required for green square", isOn: $isRequired)
                }

                Section("Where") {
                    if calendars.isEmpty {
                        Text("Loading lists…")
                    } else {
                        Picker("List", selection: Binding(
                            get: { selectedCalendar?.calendarIdentifier ?? calendars.first?.calendarIdentifier ?? "" },
                            set: { newID in
                                selectedCalendar = calendars.first(where: { $0.calendarIdentifier == newID })
                            }
                        )) {
                            ForEach(calendars, id: \.calendarIdentifier) { cal in
                                Text(cal.title).tag(cal.calendarIdentifier)
                            }
                        }
                    }
                }

                Section("Schedule") {
                    Toggle("Set due time", isOn: $hasDueTime)

                    if hasDueTime {
                        DatePicker("Time", selection: $dueTime, displayedComponents: .hourAndMinute)
                    }

                    Text("Repeats: Daily")
                        .foregroundStyle(.secondary)
                }

                if let msg = errorMessage {
                    Section {
                        Text(msg).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCalendar == nil)
                }
            }
            .task { await loadCalendars() }
        }
    }

    // MARK: - EventKit

    private func loadCalendars() async {
        errorMessage = nil

        let ok = await requestRemindersAccessIfNeeded()
        guard ok else {
            errorMessage = "Reminders access is not granted. Enable it in Settings → Privacy & Security → Reminders."
            return
        }

        let cals = store.calendars(for: .reminder)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        calendars = cals
        selectedCalendar = selectedCalendar ?? cals.first
    }

    private func save() async {
        guard let calendar = selectedCalendar else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar

            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            reminder.title = cleanTitle
            reminder.notes = "Created by HabitSquares for habit: \(habitName)"

            // ✅ Due date components (required for repeating reminders)
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())

            if hasDueTime {
                let timeComps = Calendar.current.dateComponents([.hour, .minute], from: dueTime)
                comps.hour = timeComps.hour
                comps.minute = timeComps.minute
            } else {
                // date-only due (no time) still satisfies EventKit for recurrence
                comps.hour = nil
                comps.minute = nil
            }

            reminder.dueDateComponents = comps

            // Daily recurrence
            let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
            reminder.recurrenceRules = [rule]

            try store.save(reminder, commit: true)

            onCreated(reminder, isRequired)
            dismiss()
        } catch {
            errorMessage = "Couldn’t save reminder: \(error.localizedDescription)"
        }
    }

    private func requestRemindersAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .authorized, .fullAccess:
            return true
        case .notDetermined:
            if #available(iOS 17.0, *) {
                do { return try await store.requestFullAccessToReminders() }
                catch { return false }
            } else {
                return await withCheckedContinuation { cont in
                    store.requestAccess(to: .reminder) { granted, _ in cont.resume(returning: granted) }
                }
            }
        default:
            return false
        }
    }
}
