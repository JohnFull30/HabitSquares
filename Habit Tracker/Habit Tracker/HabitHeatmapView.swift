import SwiftUI
import CoreData

/// One GitHub-style 365-day heatmap row for a single habit.
/// Layout: 7 rows (days) × ~53 columns (weeks), horizontal scroll.
struct HabitHeatmapView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Core Data habit
    @ObservedObject var habit: Habit

    // MARK: - Display tuning
    private let dayCount: Int = 365

    private let squareSize: CGFloat = 12
    private let squareCorner: CGFloat = 3
    private let squareSpacing: CGFloat = 3

    // Cache completions for fast lookup
    @State private var completionByDay: [Date: HabitCompletion] = [:]

    private var cal: Calendar {
        var c = Calendar.current
        // Keep user locale defaults; GitHub-like view still works fine.
        return c
    }

    // MARK: - Date Range

    private var todayStart: Date { cal.startOfDay(for: Date()) }

    private var rangeStart: Date {
        // Inclusive start = 364 days ago
        cal.date(byAdding: .day, value: -(dayCount - 1), to: todayStart)!
    }

    /// Align rangeStart back to the beginning of its week so columns represent weeks cleanly.
    private var alignedGridStart: Date {
        let weekday = cal.component(.weekday, from: rangeStart) // 1...7
        let delta = weekday - cal.firstWeekday
        let daysToSubtract = (delta >= 0) ? delta : (delta + 7)
        return cal.date(byAdding: .day, value: -daysToSubtract, to: rangeStart)!
    }

    /// Total grid cells: full weeks covering [alignedGridStart ... todayStart]
    private var gridCellCount: Int {
        let days = cal.dateComponents([.day], from: alignedGridStart, to: todayStart).day ?? 0
        let totalDays = days + 1
        let weeks = Int(ceil(Double(totalDays) / 7.0))
        return weeks * 7
    }

    /// Dates for each cell. Nil means “outside the 365-day window”.
    private var gridDates: [Date?] {
        (0..<gridCellCount).map { offset in
            let d = cal.date(byAdding: .day, value: offset, to: alignedGridStart)!
            if d < rangeStart || d > todayStart { return nil }
            return d
        }
    }

    private var gridRows: [GridItem] {
        Array(repeating: GridItem(.fixed(squareSize), spacing: squareSpacing), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Optional: habit name header (remove if you already show it elsewhere)
            Text(habit.name ?? "Habit")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: gridRows, spacing: squareSpacing) {
                    ForEach(Array(gridDates.enumerated()), id: \.offset) { _, date in
                        if let date {
                            square(for: date)
                        } else {
                            Color.clear
                                .frame(width: squareSize, height: squareSize)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .task { loadCompletions() }
        // iOS 17+ onChange (two-parameter form)
        .onChange(of: habit.objectID) { _, _ in
            loadCompletions()
        }
    }

    // MARK: - Square rendering

    private func square(for date: Date) -> some View {
        let key = cal.startOfDay(for: date)
        let completion = completionByDay[key]
        let isComplete = completion?.isComplete ?? false

        // Simple fill logic:
        // - Complete => green
        // - Incomplete but has a completion row => light green
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

    // MARK: - Core Data fetch (range)

    private func loadCompletions() {
        // Fetch all completions for this habit in the 365-day window
        let req = NSFetchRequest<HabitCompletion>(entityName: "HabitCompletion")

        let start = rangeStart as NSDate
        let end = todayStart as NSDate

        // Habit relationship key should be "habit" in your model.
        // If yours differs, change "habit" here.
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
