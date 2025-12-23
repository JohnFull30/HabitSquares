import SwiftUI
import CoreData

/// One row of the heatmap for a single habit.
struct HabitHeatmapView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Core Data habit
    @ObservedObject var habit: Habit

    // MARK: - Display tuning

    /// How many days to show (default 30 for cards; can be 365 in detail)
    private let dayCount: Int

    /// Grid layout (columns × rows) — also configurable for widgets/detail later
    private let columns: Int
    private var rows: Int {
        Int(ceil(Double(dayCount) / Double(columns)))
    }

    /// Visual constants
    private let squareSize: CGFloat = 12
    private let squareCorner: CGFloat = 3
    private let squareSpacing: CGFloat = 3


    // MARK: - Fetch completions

    @FetchRequest private var completions: FetchedResults<HabitCompletion>

    init(habit: Habit, dayCount: Int = 30, columns: Int = 6) {
        self._habit = ObservedObject(initialValue: habit)
        self.dayCount = dayCount
        self.columns = columns

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today

        let predicate = NSPredicate(
            format: "habit == %@ AND date >= %@ AND date <= %@",
            habit,
            start as NSDate,
            today as NSDate
        )

        _completions = FetchRequest(
            entity: HabitCompletion.entity(),
            sortDescriptors: [],
            predicate: predicate
        )
    }

    /// Dictionary keyed by start-of-day Date → HabitCompletion
    private var completionByDay: [Date: HabitCompletion] {
        let calendar = Calendar.current
        return Dictionary(
            uniqueKeysWithValues: completions.compactMap { completion in
                guard let date = completion.date else { return nil }
                let dayKey = calendar.startOfDay(for: date)
                return (dayKey, completion)
            }
        )
    }

    /// Ordered list of Dates we’ll render (oldest → newest)
    private var dayDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<dayCount).compactMap { offset in
            // We want oldest on the left, newest on the right
            let daysAgo = dayCount - 1 - offset
            return calendar.date(byAdding: .day, value: -daysAgo, to: today)
        }
    }

    // MARK: - Body

    var body: some View {
        // Card-style row so it feels closer to the mock
        VStack(alignment: .leading, spacing: 8) {
            // Title + subtitle
            Text(habit.name ?? "Habit")
                .font(.headline)
                .lineLimit(2)                       // at most 2 lines
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false,
                           vertical: true)          // allow vertical growth, not horizontal
                .frame(maxWidth: .infinity,
                       alignment: .leading)

            Text("Last \(dayCount) days")
                .font(.caption)
                .foregroundStyle(.secondary)

            // GitHub-style grid
            VStack(spacing: squareSpacing) {
                let calendar = Calendar.current

                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: squareSpacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column

                            if index < dayDates.count {
                                let date = dayDates[index]
                                let dayKey = calendar.startOfDay(for: date)
                                let completion = completionByDay[dayKey]
                                let isComplete = completion?.isComplete ?? false

                                RoundedRectangle(cornerRadius: squareCorner, style: .continuous)
                                    .fill(isComplete
                                          ? Color.green
                                          : Color(UIColor.systemGray5))
                                    .frame(width: squareSize, height: squareSize)
                            } else {
                                // Empty spacer so last row still lines up
                                Color.clear
                                    .frame(width: squareSize, height: squareSize)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.systemBackground))

        )
    }
}
