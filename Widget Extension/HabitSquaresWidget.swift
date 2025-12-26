//
//  HabitSquaresWidget.swift
//  Habit Tracker WidgetExtension
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Provider

struct HabitSquaresProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> HabitSquaresEntry {
        let config = HabitWidgetConfigurationIntent()
        let payload = loadPayload(for: config, dayCount: 60)
        return HabitSquaresEntry(date: .now, configuration: config, payload: payload)
    }

    func snapshot(for configuration: HabitWidgetConfigurationIntent, in context: Context) async -> HabitSquaresEntry {
        let payload = loadPayload(for: configuration, dayCount: 60)
        return HabitSquaresEntry(date: .now, configuration: configuration, payload: payload)
    }

    func timeline(for configuration: HabitWidgetConfigurationIntent, in context: Context) async -> Timeline<HabitSquaresEntry> {
        let payload = loadPayload(for: configuration, dayCount: 60)
        let entry = HabitSquaresEntry(date: .now, configuration: configuration, payload: payload)

        // refresh every ~30 min
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(next))
    }

    // MARK: - Loader

    private func loadPayload(for configuration: HabitWidgetConfigurationIntent,
                             dayCount: Int) -> WidgetHabitTodayPayload {

        // Your Intent likely has: @Parameter(title: "Habit") var habit: WidgetHabitEntity?
        // We'll try to read the selected habit id.
        let selectedHabitID = configuration.habit?.id

        if let hid = selectedHabitID,
           let stored = WidgetSharedStore.readToday(habitID: hid) {
            return stored
        }

        // Fallback placeholder
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"

        let days: [WidgetDay] = (0..<dayCount).map { i in
            let d = cal.date(byAdding: .day, value: i - (dayCount - 1), to: today) ?? today
            let dk = fmt.string(from: d)
            return WidgetDay(dateKey: dk, isComplete: false)
        }

        return WidgetHabitTodayPayload(
            updatedAt: Date(),
            habitID: selectedHabitID ?? "unknown",
            habitName: "Habit",
            totalRequired: 0,
            completedRequired: 0,
            isComplete: false,
            days: days
        )
    }
}

// MARK: - Entry

struct HabitSquaresEntry: TimelineEntry {
    let date: Date
    let configuration: HabitWidgetConfigurationIntent
    let payload: WidgetHabitTodayPayload
}

// MARK: - Widget

struct HabitSquaresWidget: Widget {
    let kind = "HabitSquaresWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: HabitWidgetConfigurationIntent.self,
            provider: HabitSquaresProvider()
        ) { entry in
            HabitSquaresWidgetView(entry: entry)
        }
        .configurationDisplayName("HabitSquares")
        .description("Your recent completions at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - View

struct HabitSquaresWidgetView: View {
    let entry: HabitSquaresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GeometryReader { proxy in
            let outer = proxy.size

            let inset: CGFloat = (family == .systemSmall) ? 12 : 14
            let inner = CGSize(
                width: max(1, outer.width - inset * 2),
                height: max(1, outer.height - inset * 2)
            )

            let layout = WidgetGridLayout.pick(for: family, in: inner)

            // days are expected oldest -> newest already, but sort just in case
            let sortedDays = entry.payload.days.sorted { $0.dateKey < $1.dateKey }
            let chosen = Array(sortedDays.suffix(layout.count))

            let padded: [WidgetDay?] =
                chosen.map { Optional($0) } +
                Array(repeating: nil, count: max(0, layout.count - chosen.count))

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(layout.square), spacing: layout.spacing), count: layout.columns),
                spacing: layout.spacing
            ) {
                ForEach(0..<layout.count, id: \.self) { i in
                    if let day = padded[i] {
                        RoundedRectangle(cornerRadius: layout.corner, style: .continuous)
                            .fill(day.isComplete ? Color.green : Color.secondary.opacity(0.12))
                            .frame(width: layout.square, height: layout.square)
                    } else {
                        RoundedRectangle(cornerRadius: layout.corner, style: .continuous)
                            .fill(Color.secondary.opacity(0.06))
                            .frame(width: layout.square, height: layout.square)
                    }
                }
            }
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "habitsquares://open?habit=\(entry.payload.habitID)"))
    }
}

// MARK: - Layout

struct WidgetGridLayout {
    let count: Int
    let columns: Int
    let rows: Int
    let square: CGFloat
    let spacing: CGFloat
    let corner: CGFloat

    static func pick(for family: WidgetFamily, in size: CGSize) -> WidgetGridLayout {
        let spacing: CGFloat = 3
        let corner: CGFloat = 3

        func layout(count: Int, cols: Int, rows: Int) -> WidgetGridLayout {
            let totalWSpacing = spacing * CGFloat(max(cols - 1, 0))
            let totalHSpacing = spacing * CGFloat(max(rows - 1, 0))

            let squareW = (size.width - totalWSpacing) / CGFloat(cols)
            let squareH = (size.height - totalHSpacing) / CGFloat(rows)
            let square = floor(min(squareW, squareH))

            return WidgetGridLayout(
                count: count,
                columns: cols,
                rows: rows,
                square: max(1, square),
                spacing: spacing,
                corner: corner
            )
        }

        if family == .systemSmall {
            return layout(count: 30, cols: 6, rows: 5)
        }

        let l60 = layout(count: 60, cols: 10, rows: 6)
        let l30 = layout(count: 30, cols: 6, rows: 5)

        if l60.square >= max(6, l30.square * 0.80) {
            return l60
        } else {
            return l30
        }
    }
}
