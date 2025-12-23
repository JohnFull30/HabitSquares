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

    @State private var completionByDay: [Date: HabitCompletion] = [:]

    private var cal: Calendar { Calendar.current }
    private var todayStart: Date { cal.startOfDay(for: Date()) }

    private var rangeStart: Date {
        cal.date(byAdding: .day, value: -(dayCount - 1), to: todayStart)!
    }

    private var days: [Date] {
        (0..<dayCount).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: rangeStart)
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(squareSize), spacing: squareSpacing), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: squareSpacing) {
            ForEach(days, id: \.self) { date in
                square(for: date)
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
        let isComplete = completion?.isComplete ?? false

        // Same logic you had before:
        // - Complete => green
        // - Has row but incomplete => light green
        // - No row => faint gray
        let fill: Color = {
            if isComplete { return .green }
            if completion != nil { return .green.opacity(0.25) }
            return .secondary.opacity(0.12)
        }()

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
            return "\(d). \(completion.isComplete ? "Complete" : "Not complete")"
        } else {
            return "\(d). No data"
        }
    }

    // MARK: - Core Data fetch

    private func loadCompletions() {
        let req = NSFetchRequest<HabitCompletion>(entityName: "HabitCompletion")

        let start = rangeStart as NSDate
        let end = todayStart as NSDate

        // Relationship key assumed "habit"
        req.predicate = NSPredicate(format: "habit == %@ AND date >= %@ AND date <= %@", habit, start, end)

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
            print("✗ HabitHeatmapView: failed to fetch completions:", error)
            completionByDay = [:]
        }
    }
}
