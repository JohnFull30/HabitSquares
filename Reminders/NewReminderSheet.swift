import SwiftUI
import EventKit

struct NewReminderSheet: View {
    let eventStore: EKEventStore
    let habitName: String
    let initialCalendarID: String?
    let existingReminder: EKReminder?
    let onSave: (EKReminder, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var form: ReminderFormModel

    @State private var calendars: [EKCalendar] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        eventStore: EKEventStore,
        habitName: String,
        initialCalendarID: String?,
        existingReminder: EKReminder? = nil,
        existingIsRequiredForGreenSquare: Bool = true,
        onSave: @escaping (EKReminder, Bool) -> Void
    ) {
        self.eventStore = eventStore
        self.habitName = habitName
        self.initialCalendarID = initialCalendarID
        self.existingReminder = existingReminder
        self.onSave = onSave

        if let existingReminder {
            _form = StateObject(
                wrappedValue: ReminderFormModel(
                    reminder: existingReminder,
                    isRequiredForGreenSquare: existingIsRequiredForGreenSquare
                )
            )
        } else {
            _form = StateObject(
                wrappedValue: ReminderFormModel(
                    title: "",
                    notes: "",
                    selectedCalendarID: initialCalendarID,
                    isRequiredForGreenSquare: true,
                    hasDueDate: false,
                    dueDate: .now,
                    repeatConfiguration: ReminderRepeatConfiguration(
                        kind: .daily,
                        dayInterval: 2,
                        selectedWeekdays: [.monday]
                    )
                )
            )
        }
    }

    private var isEditing: Bool {
        existingReminder != nil || form.isEditing
    }

    private var selectedCalendar: EKCalendar? {
        guard let id = form.selectedCalendarID else { return nil }
        return calendars.first(where: { $0.calendarIdentifier == id })
    }

    var body: some View {
        NavigationStack {
            Form {
                reminderSection
                whereSection
                scheduleSection

                if let msg = errorMessage {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Reminder" : "New Reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? (isEditing ? "Updating…" : "Saving…") : (isEditing ? "Update" : "Save")) {
                        Task { await save() }
                    }
                    .disabled(
                        isSaving ||
                        !form.isValid ||
                        selectedCalendar == nil
                    )
                }
            }
            .task {
                await loadCalendars()
            }
        }
    }

    // MARK: - Sections

    private var reminderSection: some View {
        Section("Reminder") {
            TextField("Title", text: $form.title)
                .textInputAutocapitalization(.sentences)

            Toggle("Required for green square", isOn: $form.isRequiredForGreenSquare)
        }
    }

    private var whereSection: some View {
        Section("Where") {
            if calendars.isEmpty {
                Text("Loading lists…")
            } else {
                Picker("List", selection: calendarSelectionBinding) {
                    ForEach(calendars, id: \.calendarIdentifier) { cal in
                        Text(cal.title).tag(Optional(cal.calendarIdentifier))
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Toggle("Set due time", isOn: $form.hasDueDate)

            if form.hasDueDate {
                DatePicker(
                    "Time",
                    selection: $form.dueDate,
                    displayedComponents: .hourAndMinute
                )
            }

            Picker("Repeat", selection: $form.repeatConfiguration.kind) {
                ForEach(ReminderRepeatKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            switch form.repeatConfiguration.kind {
            case .daily:
                EmptyView()

            case .everyXDays:
                Stepper(
                    value: everyXDaysBinding,
                    in: 2...365
                ) {
                    Text("Every \(form.repeatConfiguration.dayInterval) day\(form.repeatConfiguration.dayInterval == 1 ? "" : "s")")
                }

            case .weekly:
                weeklyPickerView

                if !form.weeklySelectionIsValid {
                    Text("Choose at least one weekday.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

            case .monthly:
                Text("Repeats monthly")
                    .foregroundStyle(.secondary)

            case .yearly:
                Text("Repeats yearly")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weeklyPickerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(ReminderWeekday.allCases) { day in
                    Button {
                        form.toggleWeekday(day)
                    } label: {
                        Text(day.shortTitle)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                form.repeatConfiguration.selectedWeekdays.contains(day)
                                ? Color.accentColor.opacity(0.18)
                                : Color.secondary.opacity(0.10)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Bindings

    private var calendarSelectionBinding: Binding<String?> {
        Binding(
            get: {
                form.selectedCalendarID ?? calendars.first?.calendarIdentifier
            },
            set: { newID in
                form.selectedCalendarID = newID
            }
        )
    }

    private var everyXDaysBinding: Binding<Int> {
        Binding(
            get: {
                max(2, form.repeatConfiguration.dayInterval)
            },
            set: { newValue in
                form.repeatConfiguration.dayInterval = max(2, newValue)
            }
        )
    }

    // MARK: - EventKit

    private func loadCalendars() async {
        let ok = await requestRemindersAccessIfNeeded()
        guard ok else {
            await MainActor.run {
                errorMessage = "Reminders access is not granted. Enable it in Settings > Privacy & Security > Reminders."
            }
            return
        }

        let cals = eventStore.calendars(for: .reminder)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let systemDefaultID = eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
        let existingReminderCalendarID = existingReminder?.calendar.calendarIdentifier

        let resolvedCalendarID =
            cals.first(where: { $0.calendarIdentifier == existingReminderCalendarID })?.calendarIdentifier
            ?? cals.first(where: { $0.calendarIdentifier == initialCalendarID })?.calendarIdentifier
            ?? cals.first(where: { $0.calendarIdentifier == systemDefaultID })?.calendarIdentifier
            ?? cals.first(where: { $0.allowsContentModifications })?.calendarIdentifier
            ?? cals.first?.calendarIdentifier

        await MainActor.run {
            calendars = cals

            if form.selectedCalendarID == nil {
                form.selectedCalendarID = resolvedCalendarID
            }
        }
    }

    private func save() async {
        guard let calendar = selectedCalendar else { return }
        guard form.isValid else { return }

        await MainActor.run {
            isSaving = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isSaving = false
            }
        }

        do {
            let reminder = existingReminder ?? EKReminder(eventStore: eventStore)

            reminder.calendar = calendar
            reminder.title = form.trimmedTitle

            if form.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if existingReminder == nil {
                    reminder.notes = "Created by HabitSquares for habit: \(habitName)"
                }
            } else {
                reminder.notes = form.notes
            }

            reminder.dueDateComponents = form.dueDateComponents()
            reminder.recurrenceRules = [form.repeatConfiguration.makeRecurrenceRule()].compactMap { $0 }

            try eventStore.save(reminder, commit: true)

            await MainActor.run {
                onSave(reminder, form.isRequiredForGreenSquare)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Couldn’t save reminder: \(error.localizedDescription)"
            }
        }
    }

    private func requestRemindersAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            return true

        case .writeOnly:
            return false

        case .notDetermined:
            if #available(iOS 17.0, *) {
                do { return try await eventStore.requestFullAccessToReminders() }
                catch { return false }
            } else {
                return await withCheckedContinuation { cont in
                    eventStore.requestAccess(to: .reminder) { granted, _ in
                        cont.resume(returning: granted)
                    }
                }
            }

        case .denied, .restricted:
            return false

        @unknown default:
            return false
        }
    }
}
