//
//  CalendarHeatmapGridView.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/12/26.
//


import SwiftUI

struct CalendarHeatmapGridView: View {
    let columns: [HeatmapWeekColumn]
    let fillForDate: (Date) -> Color

    private let squareSize: CGFloat = 10
    private let squareCorner: CGFloat = 3
    private let squareSpacing: CGFloat = 2

    private let weekdayLabelWidth: CGFloat = 10
    private let weekLabelHeight: CGFloat = 10

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            weekLabelsRow
            heatmapGrid
        }
    }

    private var weekLabelsRow: some View {
        HStack(alignment: .center, spacing: 4) {
            Color.clear
                .frame(width: weekdayLabelWidth, height: weekLabelHeight)

            HStack(alignment: .center, spacing: squareSpacing) {
                ForEach(columns) { column in
                    Text(weekNumberLabel(for: column.weekStart))
                        .font(.system(size: 6, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: squareSize, height: weekLabelHeight, alignment: .center)
                }
            }
        }
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: 4) {
            weekdayLabelsColumn

            HStack(alignment: .top, spacing: squareSpacing) {
                ForEach(columns) { column in
                    VStack(spacing: squareSpacing) {
                        ForEach(column.cells) { cell in
                            square(for: cell)
                        }
                    }
                }
            }
        }
    }

    private var weekdayLabelsColumn: some View {
        VStack(alignment: .trailing, spacing: squareSpacing) {
            ForEach(0..<7, id: \.self) { rowIndex in
                Text(HabitHeatmapBuilder.weekdayLabel(for: rowIndex))
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: weekdayLabelWidth, height: squareSize, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func square(for cell: HeatmapDayCell) -> some View {
        if cell.isPadding || cell.date == nil {
            RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
                .fill(Color.clear)
                .frame(width: squareSize, height: squareSize)
        } else if let date = cell.date {
            RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
                .fill(fillForDate(date))
                .overlay {
                    if cell.isToday {
                        RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
                            .stroke(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
                .frame(width: squareSize, height: squareSize)
        }
    }

    private func weekNumberLabel(for weekStart: Date) -> String {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        return "\(cal.component(.weekOfYear, from: weekStart))"
    }
}