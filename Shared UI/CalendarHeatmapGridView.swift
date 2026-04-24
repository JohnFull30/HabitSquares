import SwiftUI

struct CalendarHeatmapGridView: View {
    let columns: [HeatmapWeekColumn]
    let fillForDate: (Date) -> Color
    let compactLayout: Bool

    private var cellSize: CGFloat { compactLayout ? 12 : 14 }
    private var cellSpacing: CGFloat { compactLayout ? 2 : 3 }
    private var columnSpacing: CGFloat { compactLayout ? 2 : 2 }
    private var weekdayLabelWidth: CGFloat { compactLayout ? 12 : 14 }
    private var monthLabelHeight: CGFloat { compactLayout ? 11 : 12 }
    private var weekLabelHeight: CGFloat { compactLayout ? 11 : 12 }
    
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
                    let label = HeatmapHeaderFormatter.monthMarker(
                        for: column,
                        at: index,
                        in: columns
                    )
                    
                    ZStack(alignment: .leading) {
                        Color.clear
                            .frame(width: cellSize, height: monthLabelHeight)
                        
                        if !label.isEmpty {
                            Text(label)
                                .font(.system(size: compactLayout ? 9 : 10, weight: .regular, design: .default))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .allowsTightening(true)
                        }
                    }
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
                                            .stroke(Color.primary.opacity(0.95), lineWidth: 2)

                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(Color.primary.opacity(0.08))
                                            .padding(2.5)
                                    }                                }
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
