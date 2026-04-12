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
    private static let fixedWeekColumnCount = 6

    static func build30DayGrid(
        endingAt endDate: Date = Date(),
        completedDates: Set<Date>,
        calendar inputCalendar: Calendar = .current
    ) -> [HeatmapWeekColumn] {
        var calendar = inputCalendar
        calendar.firstWeekday = 2 // Monday

        let normalizedEndDate = calendar.startOfDay(for: endDate)

        guard let normalizedStartDate = calendar.date(byAdding: .day, value: -29, to: normalizedEndDate),
              let endWeekStart = startOfWeek(for: normalizedEndDate, calendar: calendar)
        else {
            return []
        }

        let normalizedCompletedDates = Set(
            completedDates.map { calendar.startOfDay(for: $0) }
        )

        guard let firstVisibleWeekStart = calendar.date(
            byAdding: .day,
            value: -7 * (fixedWeekColumnCount - 1),
            to: endWeekStart
        ) else {
            return []
        }

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.dateFormat = "MMM"

        let weekStarts: [Date] = (0..<fixedWeekColumnCount).compactMap { offset in
            calendar.date(byAdding: .day, value: 7 * offset, to: firstVisibleWeekStart)
        }

        return weekStarts.enumerated().map { index, weekStart in
            let cells: [HeatmapDayCell] = (0..<7).compactMap { weekdayOffset in
                guard let cellDate = calendar.date(byAdding: .day, value: weekdayOffset, to: weekStart) else {
                    return nil
                }

                let normalizedCellDate = calendar.startOfDay(for: cellDate)
                let isInsideVisibleRange =
                    normalizedCellDate >= normalizedStartDate &&
                    normalizedCellDate <= normalizedEndDate

                if !isInsideVisibleRange {
                    return HeatmapDayCell(
                        date: nil,
                        isComplete: false,
                        isToday: false,
                        isPadding: true
                    )
                }

                let isComplete = normalizedCompletedDates.contains(normalizedCellDate)
                let isToday = calendar.isDate(normalizedCellDate, inSameDayAs: normalizedEndDate)

                return HeatmapDayCell(
                    date: normalizedCellDate,
                    isComplete: isComplete,
                    isToday: isToday,
                    isPadding: false
                )
            }

            let monthLabel = monthLabelForWeekColumn(
                weekStart: weekStart,
                columnIndex: index,
                calendar: calendar,
                formatter: monthFormatter
            )

            return HeatmapWeekColumn(
                weekStart: weekStart,
                cells: cells,
                monthLabel: monthLabel
            )
        }
    }

    static func weekdayLabel(for rowIndex: Int) -> String {
        switch rowIndex {
        case 0: return "M"
        case 1: return "T"
        case 2: return "W"
        case 3: return "H"
        case 4: return "F"
        case 5: return "S"
        case 6: return "U"
        default: return ""
        }
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    private static func monthLabelForWeekColumn(
        weekStart: Date,
        columnIndex: Int,
        calendar: Calendar,
        formatter: DateFormatter
    ) -> String? {
        if columnIndex == 0 {
            return formatter.string(from: weekStart)
        }

        let previousWeek = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let previousMonth = calendar.component(.month, from: previousWeek)
        let currentMonth = calendar.component(.month, from: weekStart)

        if previousMonth != currentMonth {
            return formatter.string(from: weekStart)
        }

        return nil
    }
}
