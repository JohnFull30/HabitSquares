import Foundation

struct HeatmapDayCell: Identifiable, Hashable {
    let id: String
    let date: Date?
    let isComplete: Bool
    let isToday: Bool
    let isPadding: Bool

    init(date: Date?, isComplete: Bool, isToday: Bool, isPadding: Bool) {
        self.date = date
        self.isComplete = isComplete
        self.isToday = isToday
        self.isPadding = isPadding

        if let date {
            self.id = "day-\(date.timeIntervalSince1970)"
        } else {
            self.id = UUID().uuidString
        }
    }
}

struct HeatmapWeekColumn: Identifiable, Hashable {
    let id: String
    let weekStart: Date
    let cells: [HeatmapDayCell]   // Always 7 cells, Monday -> Sunday
    let monthLabel: String?

    init(weekStart: Date, cells: [HeatmapDayCell], monthLabel: String?) {
        self.weekStart = weekStart
        self.cells = cells
        self.monthLabel = monthLabel
        self.id = "week-\(weekStart.timeIntervalSince1970)"
    }
}

enum HabitHeatmapBuilder {
    static func build30DayGrid(
        endingAt endDate: Date,
        completedDates: Set<Date>,
        calendar: Calendar = .current
    ) -> [HeatmapWeekColumn] {
        buildGrid(
            dayCount: 30,
            endingAt: endDate,
            completedDates: completedDates,
            calendar: calendar
        )
    }

    static func buildGrid(
        dayCount: Int,
        endingAt endDate: Date,
        completedDates: Set<Date>,
        calendar: Calendar = .current
    ) -> [HeatmapWeekColumn] {
        guard dayCount > 0 else { return [] }

        let normalizedEnd = calendar.startOfDay(for: endDate)

        guard let rawStartDate = calendar.date(
            byAdding: .day,
            value: -(dayCount - 1),
            to: normalizedEnd
        ) else {
            return []
        }

        // Expand the visible range to full Monday -> Sunday weeks
        let startWeekday = mondayFirstWeekdayIndex(for: rawStartDate, calendar: calendar)
        let expandedStartDate = calendar.date(
            byAdding: .day,
            value: -startWeekday,
            to: rawStartDate
        ) ?? rawStartDate

        let endWeekday = mondayFirstWeekdayIndex(for: normalizedEnd, calendar: calendar)
        let trailingDaysNeeded = 6 - endWeekday
        let expandedEndDate = calendar.date(
            byAdding: .day,
            value: trailingDaysNeeded,
            to: normalizedEnd
        ) ?? normalizedEnd

        let normalizedCompleted = Set(
            completedDates.map { calendar.startOfDay(for: $0) }
        )

        var allDays: [Date] = []
        var cursor = expandedStartDate

        while cursor <= expandedEndDate {
            allDays.append(cursor)

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        guard let firstRealDate = allDays.first else { return [] }

        var columns: [HeatmapWeekColumn] = []
        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.dateFormat = "MMM"

        for chunkStart in stride(from: 0, to: allDays.count, by: 7) {
            let chunkEnd = min(chunkStart + 7, allDays.count)
            let weekDates = Array(allDays[chunkStart..<chunkEnd])

            let cells = weekDates.map { day in
                let normalizedDay = calendar.startOfDay(for: day)
                return HeatmapDayCell(
                    date: normalizedDay,
                    isComplete: normalizedCompleted.contains(normalizedDay),
                    isToday: calendar.isDateInToday(normalizedDay),
                    isPadding: false
                )
            }

            let weekStartDate = weekDates.first ?? firstRealDate

            let monthLabel: String?
            if let firstDateInColumn = weekDates.first {
                let currentMonth = calendar.component(.month, from: firstDateInColumn)

                if let previousFirstDate = columns.last?.cells.compactMap(\.date).first {
                    let previousMonth = calendar.component(.month, from: previousFirstDate)
                    monthLabel = previousMonth == currentMonth
                        ? nil
                        : monthFormatter.string(from: firstDateInColumn)
                } else {
                    monthLabel = monthFormatter.string(from: firstDateInColumn)
                }
            } else {
                monthLabel = nil
            }

            columns.append(
                HeatmapWeekColumn(
                    weekStart: weekStartDate,
                    cells: cells,
                    monthLabel: monthLabel
                )
            )
        }

        return columns
    }

    static func weekdayLabel(for rowIndex: Int) -> String {
        let labels = ["M", "T", "W", "H", "F", "S", "U"]
        guard labels.indices.contains(rowIndex) else { return "" }
        return labels[rowIndex]
    }

    private static func mondayFirstWeekdayIndex(
        for date: Date,
        calendar: Calendar
    ) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }
}
