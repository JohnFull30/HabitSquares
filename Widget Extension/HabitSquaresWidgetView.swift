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
        VStack(alignment: .leading, spacing: 4) {

            Text(titleText)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            GeometryReader { proxy in
                let outer = proxy.size

                let inset: CGFloat = (family == .systemSmall) ? 6 : 5
                let inner = CGSize(
                    width: max(1, outer.width - inset * 2),
                    height: max(1, outer.height - inset * 2)
                )

                let layout = WidgetGridLayout.pick(for: family, in: inner)

                // ✅ snapshot (not payload)
                let sortedDays = entry.snapshot.days.sorted { $0.dateKey < $1.dateKey }
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
