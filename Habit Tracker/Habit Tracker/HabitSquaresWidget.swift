//
//  HabitSquaresWidget.swift
//  Habit Tracker WidgetExtension
//

import WidgetKit
import SwiftUI

// MARK: - Provider

struct HabitSquaresProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitSquaresEntry {
        HabitSquaresEntry(date: .now, snapshot: WidgetSnapshotStore.placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitSquaresEntry) -> Void) {
        let snap = WidgetSnapshotStore.load() ?? WidgetSnapshotStore.placeholder()
        completion(HabitSquaresEntry(date: .now, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitSquaresEntry>) -> Void) {
        let snap = WidgetSnapshotStore.load() ?? WidgetSnapshotStore.placeholder()
        let entry = HabitSquaresEntry(date: .now, snapshot: snap)

        // Fallback refresh (your app also reloads timelines when it writes a snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Entry

struct HabitSquaresEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Widget

struct HabitSquaresWidget: Widget {
    let kind = "HabitSquaresWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitSquaresProvider()) { entry in
            HabitSquaresWidgetView(entry: entry)
        }
        .configurationDisplayName("HabitSquares")
        .description("Your recent completions at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // NOTE: Do NOT disable margins — we want a clean centered look, not edge-to-edge stretch.
        // .contentMarginsDisabled()
    }
}

// MARK: - View

struct HabitSquaresWidgetView: View {
    let entry: HabitSquaresEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GeometryReader { proxy in
            let outer = proxy.size

            // Inner padding so it feels like your app card, not stretched.
            let inset: CGFloat = (family == .systemSmall) ? 12 : 14
            let inner = CGSize(
                width: max(1, outer.width - inset * 2),
                height: max(1, outer.height - inset * 2)
            )

            let layout = WidgetGridLayout.pick(for: family, in: inner)

            // Sort to guarantee correct placement (oldest -> newest).
            let sortedDays = entry.snapshot.days.sorted { $0.dateKey < $1.dateKey }

            // Take the last N (most recent), keep chronological order so newest ends bottom-right.
            let chosen = Array(sortedDays.suffix(layout.count))

            // Pad if needed so the grid stays full
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
        .widgetURL(URL(string: "habitsquares://open"))
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

        // Small always 30 in a nice 6×5.
        if family == .systemSmall {
            return layout(count: 30, cols: 6, rows: 5)
        }

        // Medium: try 60 (10×6) IF it still looks good; otherwise use 30 (6×5) bigger squares.
        let l60 = layout(count: 60, cols: 10, rows: 6)
        let l30 = layout(count: 30, cols: 6, rows: 5)

        // If 60-day squares are at least 80% of the 30-day square size AND not tiny, pick 60.
        if l60.square >= max(6, l30.square * 0.80) {
            return l60
        } else {
            return l30
        }
    }
}
