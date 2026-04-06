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

    var body: some View {
        Group {
            if family == .systemSmall {
                smallWidgetBody
            } else {
                mediumWidgetBody
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(widgetURL)
    }

    // MARK: - Small

    private var smallWidgetBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                titleFont: .system(size: 15, weight: .semibold),
                statusFont: .system(size: 12, weight: .medium),
                headerSpacing: 2
            )
            .padding(.bottom, 8)

            gridView(inset: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Medium

    private var mediumWidgetBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                titleFont: .headline,
                statusFont: .caption,
                headerSpacing: 3
            )
            .padding(.bottom, 10)

            gridView(inset: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    @ViewBuilder
    private func header(
        titleFont: Font,
        statusFont: Font,
        headerSpacing: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            Text(titleText)
                .font(titleFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let statusText {
                Text(statusText)
                    .font(statusFont)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Grid

    private func gridView(inset: CGFloat) -> some View {
        GeometryReader { proxy in
            let outer = proxy.size
            let inner = CGSize(
                width: max(1, outer.width - inset * 2),
                height: max(1, outer.height - inset * 2)
            )

            let layout = WidgetGridLayout.pick(for: family, in: inner)

            let sorted = entry.snapshot.days.sorted { $0.dateKey < $1.dateKey }
            let chosen = Array(sorted.suffix(layout.count))

            let padCount = max(0, layout.count - chosen.count)
            let padded: [WidgetDay?] = Array(repeating: nil, count: padCount) + chosen.map(Optional.some)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(layout.square), spacing: layout.spacing),
                    count: layout.columns
                ),
                alignment: .leading,
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(inset)
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
