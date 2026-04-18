import SwiftUI
import WidgetKit

struct HabitSquaresWidgetView: View {
    let entry: HabitSquaresEntry
    @Environment(\.widgetFamily) private var family

    private let calendar = Calendar.autoupdatingCurrent

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
        entry.configuration.habit?.name ?? "Active Habits"
    }

    private var completedDates: Set<Date> {
        Set(
            parsedWidgetDays
                .filter(\.isComplete)
                .map(\.date)
        )
    }

    private var heatmapColumns: [HeatmapWeekColumn] {
        HabitHeatmapBuilder.buildGrid(
            dayCount: 366,
            endingAt: Date(),
            completedDates: completedDates,
            calendar: calendar
        )
    }

    private var parsedWidgetDays: [(date: Date, isComplete: Bool)] {
        entry.snapshot.days.compactMap { day in
            guard let date = Self.widgetDateFormatter.date(from: day.dateKey) else {
                return nil
            }

            return (
                date: calendar.startOfDay(for: date),
                isComplete: day.isComplete
            )
        }
    }

    private static let widgetDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.autoupdatingCurrent
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 2 : 4) {
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

            WidgetHeatmapGrid(
                columns: heatmapColumns,
                fillForDate: fillColor(for:)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(widgetPadding)
        .containerBackground(.background, for: .widget)
        .widgetURL(widgetURL)
    }

    private func fillColor(for date: Date) -> Color {
        let normalized = calendar.startOfDay(for: date)
        return completedDates.contains(normalized) ? .green : Color(.systemGray5)
    }

    private var widgetPadding: CGFloat {
        switch family {
        case .systemSmall:
            return 8
        case .systemMedium:
            return 10
        case .systemLarge:
            return 1
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
