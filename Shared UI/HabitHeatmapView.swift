import SwiftUI
import CoreData

struct HabitHeatmapView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var habit: Habit

    private let dayCount: Int = 49
    private let cal = Calendar.autoupdatingCurrent
    private let palette = HeatmapPalette()

    @State private var completionByDay: [Date: HabitCompletion] = [:]

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
        HabitHeatmapBuilder.buildGrid(
            dayCount: dayCount,
            endingAt: .now,
            completedDates: Set(completionByDay.keys),
            calendar: cal
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(habit.name ?? "Habit")
                .font(.headline)
                .lineLimit(1)

            CalendarHeatmapGridView(
                columns: heatmapColumns,
                fillForDate: fillColor(for:)
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(10)
        .hsCard()
        .task {
            loadCompletions()
        }
        .onChange(of: habit.objectID) { _, _ in
            loadCompletions()
        }
    }

    private func fillColor(for date: Date) -> Color {
        let key = dayKey(date)
        let completion = completionByDay[key]

        if completion?.isComplete == true {
            return .green
        }

        return palette.color(
            base: Color(hex: habit.colorHex ?? "#22C55E"),
            completed: completion.map { Int($0.completedRequired) },
            total: completion.map { Int($0.totalRequired) }
        )
    }

    private func loadCompletions() {
        let req = NSFetchRequest<HabitCompletion>(entityName: "HabitCompletion")
        req.predicate = NSPredicate(
            format: "habit == %@ AND date >= %@ AND date < %@",
            habit,
            rangeStart as NSDate,
            tomorrowStart as NSDate
        )
        req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

        do {
            let results = try viewContext.fetch(req)
            var dict: [Date: HabitCompletion] = [:]
            dict.reserveCapacity(results.count)

            for completion in results {
                if let date = completion.date {
                    dict[dayKey(date)] = completion
                }
            }

            completionByDay = dict
        } catch {
            print("HabitHeatmapView loadCompletions error:", error)
            completionByDay = [:]
        }
    }
}
