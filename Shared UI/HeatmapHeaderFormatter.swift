import Foundation

enum HeatmapHeaderFormatter {
    static func monthMarker(
        for column: HeatmapWeekColumn,
        at index: Int,
        in columns: [HeatmapWeekColumn],
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        guard let currentDate = column.cells.compactMap(\.date).first else { return "" }

        if index == 0 {
            return shortMonthFormatter.string(from: currentDate)
        }

        guard let previousDate = columns[index - 1].cells.compactMap(\.date).first else {
            return shortMonthFormatter.string(from: currentDate)
        }

        let currentMonth = calendar.component(.month, from: currentDate)
        let previousMonth = calendar.component(.month, from: previousDate)

        return currentMonth != previousMonth ? shortMonthFormatter.string(from: currentDate) : ""
    }

    static func isoWeekNumber(
        for column: HeatmapWeekColumn,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        guard let firstRealDate = column.cells.compactMap(\.date).first else { return "" }

        var isoCalendar = calendar
        isoCalendar.firstWeekday = 2
        isoCalendar.minimumDaysInFirstWeek = 4

        let week = isoCalendar.component(.weekOfYear, from: firstRealDate)
        return String(week)
    }

    private static let shortMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()
}
