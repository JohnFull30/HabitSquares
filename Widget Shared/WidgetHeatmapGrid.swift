import SwiftUI
import WidgetKit

struct WidgetHeatmapGrid: View {
    let columns: [HeatmapWeekColumn]
    let fillForDate: (Date) -> Color

    var body: some View {
        GeometryReader { geo in
            let fit = makeFit(in: geo.size)
            let visibleColumns = Array(columns.suffix(fit.visibleColumnCount))
            let layout = makeLayout(in: geo.size, columnCount: visibleColumns.count)

            HStack(alignment: .top, spacing: layout.outerSpacing) {
                weekdayLabels(layout: layout)

                VStack(alignment: .leading, spacing: layout.topToGridSpacing) {
                    topLabels(columns: visibleColumns, layout: layout)
                    gridColumns(columns: visibleColumns, layout: layout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    private func weekdayLabels(layout: LayoutMetrics) -> some View {
        VStack(alignment: .trailing, spacing: layout.cellSpacing) {
            Color.clear
                .frame(
                    width: layout.weekdayLabelWidth,
                    height: layout.monthLabelHeight + layout.weekLabelHeight
                )

            ForEach(0..<7, id: \.self) { rowIndex in
                Text(HabitHeatmapBuilder.weekdayLabel(for: rowIndex))
                    .font(.system(size: layout.weekdayFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: layout.weekdayLabelWidth,
                        height: layout.cellSize,
                        alignment: .trailing
                    )
            }
        }
    }

    private func topLabels(columns: [HeatmapWeekColumn], layout: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: layout.columnSpacing) {
                ForEach(Array(columns.enumerated()), id: \.1.id) { index, column in
                    Text(
                        HeatmapHeaderFormatter.monthMarker(
                            for: column,
                            at: index,
                            in: columns
                        )
                    )
                    .font(.system(size: layout.topLabelFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: layout.cellSize, height: layout.monthLabelHeight)
                }
            }

            HStack(alignment: .bottom, spacing: layout.columnSpacing) {
                ForEach(columns) { column in
                    Text(HeatmapHeaderFormatter.isoWeekNumber(for: column))
                        .font(.system(size: layout.topLabelFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: layout.cellSize, height: layout.weekLabelHeight)
                }
            }
        }
    }

    private func gridColumns(columns: [HeatmapWeekColumn], layout: LayoutMetrics) -> some View {
        HStack(alignment: .top, spacing: layout.columnSpacing) {
            ForEach(columns) { column in
                VStack(spacing: layout.cellSpacing) {
                    ForEach(column.cells) { cell in
                        if let date = cell.date, !cell.isPadding {
                            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                .fill(fillForDate(date))
                                .overlay {
                                    if cell.isToday {
                                        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                                            .stroke(
                                                Color.secondary.opacity(0.75),
                                                lineWidth: layout.todayStrokeWidth
                                            )
                                    }
                                }
                                .frame(width: layout.cellSize, height: layout.cellSize)
                        } else {
                            Color.clear
                                .frame(width: layout.cellSize, height: layout.cellSize)
                        }
                    }
                }
                .frame(width: layout.cellSize)
            }
        }
    }

    private func makeFit(in size: CGSize) -> FitMetrics {
        let weekdayLabelWidth = max(7, size.width * 0.035)
        let outerSpacing = max(2, size.width * 0.006)
        let columnSpacing = max(1, size.width * 0.0025)
        let minCellSize: CGFloat = 11

        let availableGridWidth = size.width - weekdayLabelWidth - outerSpacing

        let visibleColumnCount = max(
            4,
            min(
                columns.count,
                Int((availableGridWidth + columnSpacing) / (minCellSize + columnSpacing))
            )
        )

        return FitMetrics(visibleColumnCount: visibleColumnCount)
    }

    private func makeLayout(in size: CGSize, columnCount: Int) -> LayoutMetrics {
        let safeColumnCount = max(columnCount, 1)

        let weekdayLabelWidth = max(7, size.width * 0.03)
        let outerSpacing = max(2, size.width * 0.005)
        let columnSpacing = max(1, size.width * 0.0022)
        let cellSpacing = max(1.5, size.height * 0.0035)
        let monthLabelHeight = max(8, size.height * 0.032)
        let weekLabelHeight = max(8, size.height * 0.032)
        let topToGridSpacing = max(2, size.height * 0.0035)
        
        let availableGridWidth = size.width - weekdayLabelWidth - outerSpacing
        let availableGridHeight = size.height - monthLabelHeight - weekLabelHeight - topToGridSpacing

        let widthCell =
            (availableGridWidth - (CGFloat(safeColumnCount - 1) * columnSpacing))
            / CGFloat(safeColumnCount)

        let heightCell =
            (availableGridHeight - (CGFloat(7 - 1) * cellSpacing))
            / CGFloat(7)

        let cellSize = max(8, floor(min(widthCell, heightCell)))

        return LayoutMetrics(
            cellSize: cellSize,
            cellSpacing: cellSpacing,
            columnSpacing: columnSpacing,
            outerSpacing: outerSpacing,
            weekdayLabelWidth: weekdayLabelWidth,
            weekdayFontSize: max(6, cellSize * 0.7),
            monthLabelHeight: monthLabelHeight,
            weekLabelHeight: weekLabelHeight,
            topLabelFontSize: max(6, cellSize * 0.62),
            topToGridSpacing: topToGridSpacing,
            cornerRadius: max(2, cellSize * 0.28),
            todayStrokeWidth: max(1, cellSize * 0.1)
        )
    }
}

private struct FitMetrics {
    let visibleColumnCount: Int
}

private struct LayoutMetrics {
    let cellSize: CGFloat
    let cellSpacing: CGFloat
    let columnSpacing: CGFloat
    let outerSpacing: CGFloat
    let weekdayLabelWidth: CGFloat
    let weekdayFontSize: CGFloat
    let monthLabelHeight: CGFloat
    let weekLabelHeight: CGFloat
    let topLabelFontSize: CGFloat
    let topToGridSpacing: CGFloat
    let cornerRadius: CGFloat
    let todayStrokeWidth: CGFloat
}
