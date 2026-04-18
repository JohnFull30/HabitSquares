import SwiftUI

struct CalendarHeatmapGridView: View {
    let columns: [HeatmapWeekColumn]
    let fillForDate: (Date) -> Color

    private let cellSize: CGFloat = 16
    private let cellSpacing: CGFloat = 4
    private let columnSpacing: CGFloat = 2
    private let weekdayLabelWidth: CGFloat = 14
    private let monthLabelHeight: CGFloat = 14
    private let weekLabelHeight: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            weekdayLabels

            VStack(alignment: .leading, spacing: 4) {
                topLabels
                gridColumns
            }
        }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: cellSpacing) {
            Color.clear
                .frame(width: weekdayLabelWidth, height: monthLabelHeight + weekLabelHeight)

            ForEach(0..<7, id: \.self) { rowIndex in
                Text(HabitHeatmapBuilder.weekdayLabel(for: rowIndex))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: weekdayLabelWidth, height: cellSize, alignment: .trailing)
            }
        }
    }

    private var topLabels: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: columnSpacing) {
                ForEach(Array(columns.enumerated()), id: \.1.id) { index, column in
                    Text(
                        HeatmapHeaderFormatter.monthMarker(
                            for: column,
                            at: index,
                            in: columns
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: cellSize, height: monthLabelHeight)
                }
            }

            HStack(alignment: .bottom, spacing: columnSpacing) {
                ForEach(columns) { column in
                    Text(HeatmapHeaderFormatter.isoWeekNumber(for: column))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: cellSize, height: weekLabelHeight)
                }
            }
        }
    }

    private var gridColumns: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(columns) { column in
                VStack(spacing: cellSpacing) {
                    ForEach(column.cells) { cell in
                        if let date = cell.date, !cell.isPadding {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(fillForDate(date))
                                .overlay {
                                    if cell.isToday {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.75), lineWidth: 1.4)
                                    }
                                }
                                .frame(width: cellSize, height: cellSize)
                        } else {
                            Color.clear
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
                .frame(width: cellSize)
            }
        }
    }
}
