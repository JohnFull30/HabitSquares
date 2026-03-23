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
        let result = loadWidgetData(for: config)
        return HabitSquaresEntry(
            date: .now,
            configuration: config,
            snapshot: result.snapshot,
            selectedHabitPayload: result.payload
        )
    }

    func snapshot(for configuration: HabitWidgetConfigurationIntent, in context: Context) async -> HabitSquaresEntry {
        let result = loadWidgetData(for: configuration)
        return HabitSquaresEntry(
            date: .now,
            configuration: configuration,
            snapshot: result.snapshot,
            selectedHabitPayload: result.payload
        )
    }

    func timeline(for configuration: HabitWidgetConfigurationIntent, in context: Context) async -> Timeline<HabitSquaresEntry> {
        let result = loadWidgetData(for: configuration)
        let entry = HabitSquaresEntry(
            date: .now,
            configuration: configuration,
            snapshot: result.snapshot,
            selectedHabitPayload: result.payload
        )

        // Conservative refresh cadence; you also manually trigger reloads from the app.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    // MARK: Snapshot loader

    private func loadWidgetData(
        for configuration: HabitWidgetConfigurationIntent
    ) -> (snapshot: WidgetSnapshot, payload: WidgetHabitTodayPayload?) {

        if let selectedHabitID = configuration.habit?.id,
           let payload = WidgetSharedStore.readToday(habitID: selectedHabitID) {

            let snapshot = WidgetSnapshot(
                updatedAt: payload.updatedAt,
                days: payload.days,
                totalHabits: 1,
                completeHabits: payload.isComplete ? 1 : 0
            )

            return (snapshot, payload)
        }

        if let snap = WidgetSharedStore.readSnapshot() {
            return (snap, nil)
        }

        return (WidgetSnapshotStore.placeholder(dayCount: 60), nil)
    }
}

// MARK: - Entry

struct HabitSquaresEntry: TimelineEntry {
    let date: Date
    let configuration: HabitWidgetConfigurationIntent
    let snapshot: WidgetSnapshot
    let selectedHabitPayload: WidgetHabitTodayPayload?
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
            ZStack {
                HabitSquaresWidgetView(entry: entry)

                #if DEBUG
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(entry.snapshot.updatedAt, style: .time)
                            .font(.caption2)
                            .opacity(0.6)
                    }
                }
                .padding(4)
                #endif
            }
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

        // Keep your preferred spacing/rounding
        let spacing: CGFloat = 4
        let corner: CGFloat = 4

        func layout(count: Int, cols: Int, rows: Int) -> WidgetGridLayout {
            let totalWSpacing = spacing * CGFloat(max(cols - 1, 0))
            let totalHSpacing = spacing * CGFloat(max(rows - 1, 0))

            let sqW = (size.width - totalWSpacing) / CGFloat(cols)
            let sqH = (size.height - totalHSpacing) / CGFloat(rows)
            let square = floor(min(sqW, sqH))

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
            // 30-day grid
            return layout(count: 30, cols: 6, rows: 5)
        } else {
            // 60-day grid
            return layout(count: 60, cols: 15, rows: 4)
        }
    }
}
