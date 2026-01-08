//
//  HabitSquaresWidgetView.swift
//  Habit Tracker WidgetExtension
//

import SwiftUI
import WidgetKit

struct HabitSquaresWidgetView: View {
    let entry: HabitSquaresEntry
    @Environment(\.widgetFamily) private var family

    private var titleText: String {
        entry.configuration.habit?.name ?? "Select a Habit"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            Text(titleText)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            GeometryReader { proxy in
                let outer = proxy.size

                // Inner box after padding
                let inset: CGFloat = (family == .systemSmall) ? 6 : 5
                let inner = CGSize(
                    width: max(1, outer.width - inset * 2),
                    height: max(1, outer.height - inset * 2)
                )

                let layout = WidgetGridLayout.pick(for: family, in: inner)

                // Ensure chronological order (oldest -> newest)
                let sorted = entry.snapshot.days.sorted { $0.dateKey < $1.dateKey }
                let chosen = Array(sorted.suffix(layout.count)) // still oldest->newest

                // LEFT-pad so newest lands bottom-right
                let padCount = max(0, layout.count - chosen.count)
                let padded: [WidgetDay?] = Array(repeating: nil, count: padCount) + chosen.map(Optional.some)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(layout.square), spacing: layout.spacing),
                        count: layout.columns
                    ),
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
            }
        }
        .padding(6)
        .containerBackground(.background, for: .widget)
        .widgetURL(widgetURL)
    }

    private var widgetURL: URL? {
        if let id = entry.configuration.habit?.id {
            return URL(string: "habitsquares://open?habit=\(id)")
        } else {
            return URL(string: "habitsquares://open")
        }
    }
}
