//
//  HabitHeatmapView.swift
//  Habit Tracker
//

import SwiftUI
import CoreData

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

    private let cal = Calendar.current
    private let palette = HeatmapPalette()

    @State private var completionByDay: [Date: HabitCompletion] = [:]

    // MARK: - Derived

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(squareSize), spacing: squareSpacing), count: columns)
    }

    /// Oldest -> newest so newest lands bottom-right in a row-major LazyVGrid.
    private var days: [Date] {
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(dayCount - 1), to: today)!
        return (0..<dayCount).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var rangeStart: Date {
        days.first ?? cal.startOfDay(for: Date())
    }

    private var todayStart: Date {
        cal.startOfDay(for: Date())
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            Text(habit.name ?? "Habit")
                .font(.headline)
                .lineLimit(1)

            Text("Last 30 days")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Grid
            LazyVGrid(columns: gridColumns, spacing: squareSpacing) {
                ForEach(days, id: \.self) { date in
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
        let key = cal.startOfDay(for: date)
        let completion = completionByDay[key]

        // TODO: replace with per-habit color (e.g., habit.uiColor) when you add it.
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

        // Assumes HabitCompletion has a relationship key named "habit" and attribute "date".
        req.predicate = NSPredicate(
            format: "habit == %@ AND date >= %@ AND date <= %@",
            habit,
            rangeStart as NSDate,
            todayStart as NSDate
        )

        do {
            let results = try viewContext.fetch(req)
            var dict: [Date: HabitCompletion] = [:]
            for c in results {
                if let d = c.date {
                    dict[cal.startOfDay(for: d)] = c
                }
            }
            completionByDay = dict
        } catch {
            print("HabitHeatmapView: loadCompletions failed: \(error)")
        }
    }
}
