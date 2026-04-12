//
//  HabitHeatmapView.swift
//  Habit Tracker
//

import SwiftUI
import CoreData

#if DEBUG
import WidgetKit
#endif

/// 30-day mini heatmap used inside the habit cards.
/// Compact Monday-first calendar heatmap.
/// - fixed 6 week columns
/// - 7 weekday rows (Mon -> Sun)
/// - full compact labels on both axes
struct HabitHeatmapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var habit: Habit

    // MARK: - Display tuning

    private let dayCount: Int = 30

    private let squareSize: CGFloat = 10
    private let squareCorner: CGFloat = 3
    private let squareSpacing: CGFloat = 2

    private let weekdayLabelWidth: CGFloat = 10
    private let weekLabelHeight: CGFloat = 10

    private let cal = Calendar.autoupdatingCurrent
    private let palette = HeatmapPalette()

    /// Keyed by `startOfDay` date.
    @State private var completionByDay: [Date: HabitCompletion] = [:]

    // MARK: - Date helpers

    private func dayKey(_ date: Date) -> Date {
        cal.startOfDay(for: date)
    }

    private var rangeStart: Date {
        let today = dayKey(.now)
        return cal.date(byAdding: .day, value: -(dayCount - 1), to: today)!
    }

    private var tomorrowStart: Date {
        cal.date(byAdding: .day, value: 1, to: dayKey(.now))!
    }

    private var heatmapColumns: [HeatmapWeekColumn] {
        HabitHeatmapBuilder.build30DayGrid(
            endingAt: .now,
            completedDates: Set(completionByDay.keys),
            calendar: cal
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(habit.name ?? "Habit")
                .font(.headline)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 4) {
                weekLabelsRow
                heatmapGrid
            }
        }
        .task { loadCompletions() }
        .onChange(of: habit.objectID) { _, _ in
            loadCompletions()
        }
    }

    // MARK: - Calendar layout

    private var weekLabelsRow: some View {
        HStack(alignment: .center, spacing: 4) {
            Color.clear
                .frame(width: weekdayLabelWidth, height: weekLabelHeight)

            HStack(alignment: .center, spacing: squareSpacing) {
                ForEach(heatmapColumns) { column in
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
                ForEach(heatmapColumns) { column in
                    VStack(spacing: squareSpacing) {
                        ForEach(Array(column.cells.enumerated()), id: \.element.id) { _, cell in
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

    private func weekNumberLabel(for weekStart: Date) -> String {
        var calendar = cal
        calendar.firstWeekday = 2 // Monday
        return "\(calendar.component(.weekOfYear, from: weekStart))"
    }

    // MARK: - Square rendering

    @ViewBuilder
    private func square(for cell: HeatmapDayCell) -> some View {
        if cell.isPadding || cell.date == nil {
            RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
                .fill(Color.clear)
                .frame(width: squareSize, height: squareSize)
        } else if let date = cell.date {
            let key = dayKey(date)
            let completion = completionByDay[key]

            let base = Color.green

            let fill = palette.color(
                base: base,
                completed: completion.map { Int($0.completedRequired) },
                total: completion.map { Int($0.totalRequired) }
            )

            RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
                .fill(fill)
                .overlay {
                    if cell.isToday {
                        RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
                            .stroke(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
                .frame(width: squareSize, height: squareSize)
                .accessibilityLabel(accessibilityLabel(for: date, completion: completion, isToday: cell.isToday))
        }
    }

    private func accessibilityLabel(for date: Date, completion: HabitCompletion?, isToday: Bool) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        let d = fmt.string(from: date)

        let todayPrefix = isToday ? "Today. " : ""

        if let completion {
            let status = completion.isComplete ? "Complete" : "Not complete"
            return "\(todayPrefix)\(d). \(status). \(completion.completedRequired) of \(completion.totalRequired) reminders done."
        } else {
            return "\(todayPrefix)\(d). No data."
        }
    }

    // MARK: - Core Data fetch

    private func loadCompletions() {
        let req = NSFetchRequest<HabitCompletion>(entityName: "HabitCompletion")
        req.predicate = NSPredicate(
            format: "habit == %@ AND date >= %@ AND date < %@",
            habit,
            rangeStart as NSDate,
            tomorrowStart as NSDate
        )

        do {
            let results = try viewContext.fetch(req)

            var dict: [Date: HabitCompletion] = [:]
            dict.reserveCapacity(results.count)

            for c in results {
                if let d = c.date {
                    dict[dayKey(d)] = c
                }
            }

            completionByDay = dict
        } catch {
            print("HabitHeatmapView: loadCompletions failed: \(error)")
        }
    }
}
