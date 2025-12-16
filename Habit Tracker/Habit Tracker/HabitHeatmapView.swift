import SwiftUI
import CoreData

/// One row of the heatmap for a single habit.
struct HabitHeatmapView: View {
    @Environment(\.managedObjectContext) private var viewContext

    /// Core Data habit for this row
    @ObservedObject var habit: Habit

    /// All completion records for this habit (sorted by date)
    @FetchRequest private var completions: FetchedResults<HabitCompletion>

    // MARK: - Init

    init(habit: Habit) {
        self.habit = habit

        let request: NSFetchRequest<HabitCompletion> = HabitCompletion.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \HabitCompletion.date, ascending: true)
        ]
        request.predicate = NSPredicate(format: "habit == %@", habit)

        _completions = FetchRequest(fetchRequest: request, animation: .default)
    }

    // MARK: - Heatmap config

    /// How many days to show in the heatmap row (3 weeks)
    private let daysToShow: Int = 21

    /// Oldest → newest (today) dates to show
    private var displayedDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Oldest on the left, today on the right
        return (0..<daysToShow).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    /// Find the completion entity for a given calendar day (if any)
    private func completion(for day: Date) -> HabitCompletion? {
        let calendar = Calendar.current

        return completions.first { completion in
            guard let date = completion.date else { return false }
            return calendar.isDate(date, inSameDayAs: day)
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Habit name column
            Text(habit.name ?? "Habit")
                .font(.headline)
                .frame(width: 90, alignment: .leading)

            // Heatmap squares
            HStack(spacing: 4) {
                ForEach(displayedDates, id: \.self) { day in
                    let completion = completion(for: day)
                    let isComplete = completion?.isComplete ?? false
                    let hasData = completion != nil

                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isComplete ? Color.green : Color.clear)
                        )
                        .frame(width: 14, height: 14)
                        .opacity(hasData ? 1.0 : 0.2)
                        .accessibilityLabel(
                            Text(accessibilityLabel(for: day, completion: completion))
                        )
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for day: Date, completion: HabitCompletion?) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        let dateString = formatter.string(from: day)

        guard let completion else {
            return "\(habit.name ?? "Habit") – \(dateString): no completion"
        }

        let status = completion.isComplete ? "complete" : "incomplete"
        return "\(habit.name ?? "Habit") – \(dateString): \(status)"
    }
}
