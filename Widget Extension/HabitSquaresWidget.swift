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
        let snap = loadSnapshot(for: config)
        return HabitSquaresEntry(date: .now, configuration: config, snapshot: snap)
    }

    func snapshot(for configuration: HabitWidgetConfigurationIntent, in context: Context) async -> HabitSquaresEntry {
        let snap = loadSnapshot(for: configuration)
        return HabitSquaresEntry(date: .now, configuration: configuration, snapshot: snap)
    }

    func timeline(for configuration: HabitWidgetConfigurationIntent, in context: Context) async -> Timeline<HabitSquaresEntry> {
        let snap = loadSnapshot(for: configuration)
        let entry = HabitSquaresEntry(date: .now, configuration: configuration, snapshot: snap)

        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(next))
    }

    // MARK: - Snapshot loader

    private func loadSnapshot(for configuration: HabitWidgetConfigurationIntent) -> WidgetSnapshot {

        // If a habit is selected, use that habit’s payload (grid + today status)
        if let selectedHabitID = configuration.habit?.id,
           let payload = WidgetSharedStore.readToday(habitID: selectedHabitID) {

            return WidgetSnapshot(
                updatedAt: payload.updatedAt,
                days: payload.days,
                totalHabits: 1,
                completeHabits: payload.isComplete ? 1 : 0
            )
        }

        // Otherwise fall back to overall snapshot cache (or a placeholder)
        if let snap = WidgetSharedStore.readSnapshot() {
            return snap
        }

        // Basic placeholder
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -59, to: today) ?? today

        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = .current
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"

        let days = (0..<60).map { i -> WidgetDay in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            return WidgetDay(dateKey: fmt.string(from: d), isComplete: false)
        }

        return WidgetSnapshot(updatedAt: Date(), days: days, totalHabits: 0, completeHabits: 0)
    }
}

// MARK: - Entry

struct HabitSquaresEntry: TimelineEntry {
    let date: Date
    let configuration: HabitWidgetConfigurationIntent
    let snapshot: WidgetSnapshot
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


// MARK: - Layout

struct WidgetGridLayout {
    let count: Int
    let columns: Int
    let rows: Int
    let square: CGFloat
    let spacing: CGFloat
    let corner: CGFloat

    static func pick(for family: WidgetFamily, in size: CGSize) -> WidgetGridLayout {
        let spacing: CGFloat = 4   // keep what you like
        let corner: CGFloat = 4   // keep what you like

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

        // Medium: 60-day, better aspect ratio for “wide but not tall” after the title
        return layout(count: 60, cols: 15, rows: 4)
    }}
