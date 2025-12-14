import SwiftUI
import CoreData

/// One row in the heatmap for a single Habit.
struct HabitHeatmapView: View {
    // The Core Data habit this row represents.
    @ObservedObject var habit: Habit
    
    // How many days back we show in the grid.
    private let totalDays: Int = 30

    // GitHub-style constants — tweak these to change look
    private let cellSize: CGFloat = 12      // square size
    private let cellSpacing: CGFloat = 3    // spacing between squares

    // 7 columns (Mon–Sun style)
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(cellSize), spacing: cellSpacing),
            count: 7
        )
    }

    // MARK: - Derived data

    /// Array of dates from oldest -> newest (left to right).
    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<totalDays).compactMap { offset in
            calendar.date(
                byAdding: .day,
                value: -(totalDays - 1 - offset),
                to: today
            )
        }
    }

    /// Map each day to whether that habit is complete.
    /// Adjust the relationship name if your model uses something else.
    private var completionsByDay: [Date: Bool] {
        guard let rawCompletions = habit.completions as? Set<HabitCompletion> else {
            return [:]
        }

        let calendar = Calendar.current
        var dict: [Date: Bool] = [:]

        for completion in rawCompletions {
            guard let date = completion.date else { continue }
            let day = calendar.startOfDay(for: date)
            dict[day] = completion.isComplete
        }

        return dict
    }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(habit.name ?? "Unnamed")
                .font(.headline)

            Text("Last \(totalDays) days")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(
                columns: columns,
                alignment: .leading,
                spacing: cellSpacing
            ) {
                ForEach(days, id: \.self) { day in
                    let calendar = Calendar.current
                    let key = calendar.startOfDay(for: day)
                    let isComplete = completionsByDay[key] ?? false
                    let isToday = calendar.isDateInToday(day)

                    DaySquareView(
                        isComplete: isComplete,
                        isToday: isToday
                    )
                    .accessibilityLabel(
                        accessibilityLabel(for: day, isComplete: isComplete)
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal)
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for day: Date, isComplete: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dateString = formatter.string(from: day)
        let status = isComplete ? "complete" : "incomplete"
        return "\(dateString): \(status)"
    }
}

// MARK: - Single square

private struct DaySquareView: View {
    let isComplete: Bool
    let isToday: Bool

    private var fillColor: Color {
        if isComplete {
            // Completed days
            return Color.green
        } else {
            // Empty days
            return Color.gray.opacity(0.2)
        }
    }

    private var borderColor: Color {
        if isToday {
            // Highlight today
            return Color.primary.opacity(0.8)
        } else {
            return Color.secondary.opacity(0.3)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(borderColor, lineWidth: 1)
            )
            .frame(width: 12, height: 12)   // match `cellSize`
    }
}
