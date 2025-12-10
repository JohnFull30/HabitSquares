import SwiftUI
import CoreData

/// A GitHub-style heatmap driven by Habit + HabitCompletion from Core Data.
struct HabitHeatmapView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // All habits, sorted by name.
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Habit.name, ascending: true)],
        animation: .default
    )
    private var habits: FetchedResults<Habit>

    // All completions; we'll filter to the last 30 days in-memory.
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \HabitCompletion.date, ascending: true)
        ],
        animation: .default
    )
    private var completions: FetchedResults<HabitCompletion>

    /// How many days back to show in the heatmap.
    private let dayCount: Int = 30

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Dates for the last `dayCount` days, oldest -> newest.
    private var dayRange: [Date] {
        let cal = Calendar.current
        return (0..<dayCount)
            .compactMap { offset in
                cal.date(byAdding: .day, value: -offset, to: today)
            }
            .map { cal.startOfDay(for: $0) }
            .sorted()
    }

    /// Map of (habitObjectID, startOfDay) -> HabitCompletion
    private var completionLookup: [CompletionKey: HabitCompletion] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -dayCount, to: today) ?? today

        var dict: [CompletionKey: HabitCompletion] = [:]

        for completion in completions {
            guard let habit = completion.habit,
                  let date = completion.date,
                  date >= cutoff
            else { continue }

            let day = cal.startOfDay(for: date)
            let key = CompletionKey(habitID: habit.objectID, day: day)
            dict[key] = completion
        }

        return dict
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(habits) { habit in
                    HabitRowView(
                        habit: habit,
                        days: dayRange,
                        completions: completionLookup,
                        today: today
                    )
                }
            }
            .padding()
        }
    }

    /// Key for looking up a completion by habit + day.
    fileprivate struct CompletionKey: Hashable {
        let habitID: NSManagedObjectID
        let day: Date

        func hash(into hasher: inout Hasher) {
            hasher.combine(habitID)
            hasher.combine(day.timeIntervalSince1970)
        }

        static func == (lhs: CompletionKey, rhs: CompletionKey) -> Bool {
            lhs.habitID == rhs.habitID && lhs.day == rhs.day
        }
    }
}

/// One row in the heatmap for a single Habit.
private struct HabitRowView: View {
    let habit: Habit
    let days: [Date]
    let completions: [HabitHeatmapView.CompletionKey: HabitCompletion]
    let today: Date

    private var name: String {
        habit.name ?? "Unnamed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)

            Text("Last 30 days")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        DaySquare(
                            isComplete: completion(for: day)?.isComplete ?? false,
                            isToday: Calendar.current.isDate(day, inSameDayAs: today)
                        )
                        .accessibilityLabel("\(name) on \(formatted(day))")
                    }
                }
            }
        }
    }

    private func completion(for day: Date) -> HabitCompletion? {
        let key = HabitHeatmapView.CompletionKey(habitID: habit.objectID, day: day)
        return completions[key]
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: date)
    }
}

/// A single day square in the heatmap.
private struct DaySquare: View {
    let isComplete: Bool
    let isToday: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isComplete ? Color.green : Color.gray.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(lineWidth: isToday ? 2 : 0)
                    .opacity(isToday ? 1 : 0)
            )
            .frame(width: 16, height: 16)
    }
}

#Preview {
    Text("HabitHeatmapView preview placeholder")
}
