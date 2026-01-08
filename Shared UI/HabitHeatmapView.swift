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
/// Layout: 5 rows × 6 columns (30 days). Newest day ends bottom-right.
struct HabitHeatmapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var habit: Habit

    // MARK: - Display tuning

    private let dayCount: Int = 30
    private let columns: Int = 6

    private let squareSize: CGFloat = 12
    private let squareCorner: CGFloat = 3
    private let squareSpacing: CGFloat = 3

    private let cal = Calendar.autoupdatingCurrent
    private let palette = HeatmapPalette()

    /// Keyed by `startOfDay` date.
    @State private var completionByDay: [Date: HabitCompletion] = [:]

    // MARK: - Grid

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(squareSize), spacing: squareSpacing), count: columns)
    }

    private func dayKey(_ date: Date) -> Date {
        cal.startOfDay(for: date)
    }

    /// idx: 0...dayCount-1 (oldest -> newest)
    private func dateForIndex(_ idx: Int) -> Date {
        let today = dayKey(.now)
        let offset = (dayCount - 1) - idx
        return cal.date(byAdding: .day, value: -offset, to: today)!
    }

    private var rangeStart: Date {
        dayKey(dateForIndex(0))
    }

    private var tomorrowStart: Date {
        cal.date(byAdding: .day, value: 1, to: dayKey(.now))!
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(habit.name ?? "Habit")
                .font(.headline)
                .lineLimit(1)

            Text("Last 30 days")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: gridColumns, spacing: squareSpacing) {
                ForEach(0..<dayCount, id: \.self) { idx in
                    let date = dateForIndex(idx)
                    square(for: date)
                }
            }
        }
        .task { loadCompletions() }
        .onChange(of: habit.objectID) { _, _ in
            loadCompletions()
        }
    }

    // MARK: - Square rendering

    private func square(for date: Date) -> some View {
        let key = dayKey(date)
        let completion = completionByDay[key]

        // TODO: replace with per-habit color when you add it (habit color -> base)
        let base = Color.green

        let fill = palette.color(
            base: base,
            completed: completion.map { Int($0.completedRequired) },
            total: completion.map { Int($0.totalRequired) }
        )

        return RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
            .fill(fill)
            .frame(width: squareSize, height: squareSize)
            .accessibilityLabel(accessibilityLabel(for: date, completion: completion))
    }

    private func accessibilityLabel(for date: Date, completion: HabitCompletion?) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        let d = fmt.string(from: date)

        if let completion {
            let status = completion.isComplete ? "Complete" : "Not complete"
            return "\(d). \(status). \(completion.completedRequired) of \(completion.totalRequired) reminders done."
        } else {
            return "\(d). No data."
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
