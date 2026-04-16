//
//  HabitSquaresWidgetView.swift
//  Habit Tracker WidgetExtension
//

import SwiftUI
import WidgetKit

struct HabitSquaresWidgetView: View {
    let entry: HabitSquaresEntry
    @Environment(\.widgetFamily) private var family

    private var statusText: String? {
        guard let payload = entry.selectedHabitPayload else { return nil }

        if payload.totalRequired <= 0 {
            return "No reminders"
        }

        if payload.isComplete {
            return "Done"
        }

        let remaining = max(payload.totalRequired - payload.completedRequired, 0)
        return remaining == 1 ? "1 left" : "\(remaining) left"
    }

    private var statusColor: Color {
        guard let payload = entry.selectedHabitPayload else { return .secondary }
        return payload.isComplete ? .green : .secondary
    }

    private var titleText: String {
        entry.configuration.habit?.name ?? "Select a Habit"
    }

    private var completedDates: Set<Date> {
        Set(
            parsedWidgetDays
                .filter(\.isComplete)
                .map(\.date)
        )
    }

    private var heatmapColumns: [HeatmapWeekColumn] {
        HabitHeatmapBuilder.build30DayGrid(
            endingAt: .now,
            completedDates: completedDates,
            calendar: calendar
        )
    }

    private var parsedWidgetDays: [(date: Date, isComplete: Bool)] {
        entry.snapshot.days.compactMap { day in
            guard let date = Self.widgetDateFormatter.date(from: day.dateKey) else {
                return nil
            }
            return (calendar.startOfDay(for: date), day.isComplete)
        }
    }

    private let calendar = Calendar.autoupdatingCurrent

    private static let widgetDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.autoupdatingCurrent
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
            Text(titleText)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }

            CalendarHeatmapGridView(
                columns: heatmapColumns,
                fillForDate: fillColor(for:)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(widgetScale, anchor: .topLeading)
        }
        .padding(widgetPadding)
        .containerBackground(.background, for: .widget)
        .widgetURL(widgetURL)
    }

    private func fillColor(for date: Date) -> Color {
        let key = calendar.startOfDay(for: date)
        let isComplete = completedDates.contains(key)
        return isComplete ? Color.green : Color.secondary.opacity(0.12)
    }

    private var widgetScale: CGFloat {
        switch family {
        case .systemSmall:
            return 0.94
        case .systemMedium:
            return 1.0
        default:
            return 1.0
        }
    }

    private var widgetPadding: CGFloat {
        switch family {
        case .systemSmall:
            return 8
        case .systemMedium:
            return 10
        default:
            return 8
        }
    }

    private var widgetURL: URL? {
        if let id = entry.configuration.habit?.id {
            return URL(string: "habitsquares://open?habit=\(id)")
        } else {
            return URL(string: "habitsquares://open")
        }
    }
}
