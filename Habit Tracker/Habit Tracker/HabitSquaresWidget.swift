import WidgetKit
import SwiftUI

// A simple entry for the widget timeline.
struct HabitSquaresEntry: TimelineEntry {
    let date: Date
}

// Timeline provider that just shows "now".
struct HabitSquaresProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitSquaresEntry {
        HabitSquaresEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitSquaresEntry) -> Void) {
        completion(HabitSquaresEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitSquaresEntry>) -> Void) {
        let entry = HabitSquaresEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// The actual widget view.
// For now it's just a simple label so we don't depend on Habit/HabitDay at all.
struct HabitSquaresWidgetEntryView: View {
    var entry: HabitSquaresEntry

    var body: some View {
        ZStack {
            Color(.systemBackground)
            Text("Habit Tracker")
                .font(.headline)
        }
    }
}

// The widget configuration.
@main
struct HabitSquaresWidget: Widget {
    let kind: String = "HabitSquaresWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitSquaresProvider()) { entry in
            HabitSquaresWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Habit Tracker")
        .description("Shows a simple HabitSquares placeholder widget.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    HabitSquaresWidget()
} timeline: {
    HabitSquaresEntry(date: .now)
}
