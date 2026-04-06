//
//  ReminderRepeatKind.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/5/26.
//


import Foundation
import EventKit
import Combine

enum ReminderRepeatKind: String, CaseIterable, Identifiable, Codable {
    case daily
    case everyXDays
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .everyXDays:
            return "Every X Days"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        }
    }
}

enum ReminderWeekday: Int, CaseIterable, Identifiable, Codable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    var longTitle: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }

    var ekWeekday: EKWeekday {
        switch self {
        case .sunday: return .sunday
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        }
    }

    static func from(_ ekWeekday: EKWeekday) -> ReminderWeekday? {
        switch ekWeekday {
        case .sunday: return .sunday
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        @unknown default:
            return nil
        }
    }
}

struct ReminderRepeatConfiguration: Equatable, Codable {
    var kind: ReminderRepeatKind = .daily

    /// Used by `.everyXDays`
    var dayInterval: Int = 2

    /// Used by `.weekly`
    var selectedWeekdays: Set<ReminderWeekday> = [.monday]

    var summaryText: String {
        switch kind {
        case .daily:
            return "Daily"

        case .everyXDays:
            return "Every \(dayInterval) day\(dayInterval == 1 ? "" : "s")"

        case .weekly:
            let days = ReminderWeekday.allCases
                .filter { selectedWeekdays.contains($0) }
                .map(\.shortTitle)
                .joined(separator: ", ")

            return days.isEmpty ? "Weekly" : "Weekly on \(days)"

        case .monthly:
            return "Monthly"

        case .yearly:
            return "Yearly"
        }
    }

    func makeRecurrenceRule() -> EKRecurrenceRule? {
        switch kind {
        case .daily:
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: nil
            )

        case .everyXDays:
            return EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: max(1, dayInterval),
                end: nil
            )

        case .weekly:
            let days = ReminderWeekday.allCases
                .filter { selectedWeekdays.contains($0) }
                .map { EKRecurrenceDayOfWeek($0.ekWeekday) }

            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: days.isEmpty ? nil : days,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )

        case .monthly:
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                end: nil
            )

        case .yearly:
            return EKRecurrenceRule(
                recurrenceWith: .yearly,
                interval: 1,
                end: nil
            )
        }
    }

    static func fromRecurrenceRules(_ rules: [EKRecurrenceRule]?) -> ReminderRepeatConfiguration? {
        guard let rule = rules?.first else { return nil }

        switch rule.frequency {
        case .daily:
            if rule.interval <= 1 {
                return ReminderRepeatConfiguration(
                    kind: .daily,
                    dayInterval: 2,
                    selectedWeekdays: [.monday]
                )
            } else {
                return ReminderRepeatConfiguration(
                    kind: .everyXDays,
                    dayInterval: rule.interval,
                    selectedWeekdays: [.monday]
                )
            }

        case .weekly:
            let weekdays: Set<ReminderWeekday> = Set(
                (rule.daysOfTheWeek ?? [])
                    .compactMap { ReminderWeekday.from($0.dayOfTheWeek) }
            )

            return ReminderRepeatConfiguration(
                kind: .weekly,
                dayInterval: 2,
                selectedWeekdays: weekdays.isEmpty ? [.monday] : weekdays
            )

        case .monthly:
            return ReminderRepeatConfiguration(
                kind: .monthly,
                dayInterval: 2,
                selectedWeekdays: [.monday]
            )

        case .yearly:
            return ReminderRepeatConfiguration(
                kind: .yearly,
                dayInterval: 2,
                selectedWeekdays: [.monday]
            )

        @unknown default:
            return nil
        }
    }
}

@MainActor
final class ReminderFormModel: ObservableObject {
    @Published var title: String
    @Published var notes: String
    @Published var selectedCalendarID: String?
    @Published var isRequiredForGreenSquare: Bool

    /// We keep date + time in one Date for form convenience.
    /// Save logic can later convert this into DateComponents for EventKit.
    @Published var hasDueDate: Bool
    @Published var dueDate: Date

    @Published var repeatConfiguration: ReminderRepeatConfiguration

    /// Holds the EKReminder identifier when editing an existing reminder.
    let existingReminderID: String?

    var isEditing: Bool {
        existingReminderID != nil
    }

    init(
        title: String = "",
        notes: String = "",
        selectedCalendarID: String? = nil,
        isRequiredForGreenSquare: Bool = true,
        hasDueDate: Bool = false,
        dueDate: Date = Date(),
        repeatConfiguration: ReminderRepeatConfiguration = ReminderRepeatConfiguration(),
        existingReminderID: String? = nil
    ) {
        self.title = title
        self.notes = notes
        self.selectedCalendarID = selectedCalendarID
        self.isRequiredForGreenSquare = isRequiredForGreenSquare
        self.hasDueDate = hasDueDate
        self.dueDate = dueDate
        self.repeatConfiguration = repeatConfiguration
        self.existingReminderID = existingReminderID
    }

    convenience init(
        reminder: EKReminder,
        isRequiredForGreenSquare: Bool = true
    ) {
        let dueDate = reminder.dueDateComponents?.date ?? Date()
        let hasDueDate = reminder.dueDateComponents != nil
        let repeatConfiguration = ReminderRepeatConfiguration
            .fromRecurrenceRules(reminder.recurrenceRules)
            ?? ReminderRepeatConfiguration()

        self.init(
            title: reminder.title,
            notes: reminder.notes ?? "",
            selectedCalendarID: reminder.calendar.calendarIdentifier,
            isRequiredForGreenSquare: isRequiredForGreenSquare,
            hasDueDate: hasDueDate,
            dueDate: dueDate,
            repeatConfiguration: repeatConfiguration,
            existingReminderID: reminder.calendarItemIdentifier
        )
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedTitle.isEmpty && weeklySelectionIsValid
    }

    var weeklySelectionIsValid: Bool {
        if repeatConfiguration.kind == .weekly {
            return !repeatConfiguration.selectedWeekdays.isEmpty
        }
        return true
    }

    func toggleWeekday(_ day: ReminderWeekday) {
        if repeatConfiguration.selectedWeekdays.contains(day) {
            repeatConfiguration.selectedWeekdays.remove(day)
        } else {
            repeatConfiguration.selectedWeekdays.insert(day)
        }
    }

    func dueDateComponents(using calendar: Calendar = .current) -> DateComponents? {
        guard hasDueDate else { return nil }

        let components: Set<Calendar.Component> = [
            .year, .month, .day, .hour, .minute
        ]
        return calendar.dateComponents(components, from: dueDate)
    }

    func recurrenceRule() -> EKRecurrenceRule? {
        repeatConfiguration.makeRecurrenceRule()
    }
}
