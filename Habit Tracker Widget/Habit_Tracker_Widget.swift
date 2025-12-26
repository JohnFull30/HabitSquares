//
//  Habit_Tracker_Widget.swift
//  Habit Tracker Widget
//
//  Created by John Fuller on 11/20/25.
//

import WidgetKit
import SwiftUI
import Foundation

// MARK: - Widget Cache Helpers
private let appGroupID = "group.com.john.habitsquares" // Must match your App/Widget capabilities
private let cacheFileName = "heatmap.json"

private struct HeatmapCacheLocal: Codable {
    let countsByDay: [String: Int]
}

private func isoDayKey(_ date: Date) -> String {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let comps = cal.dateComponents([.year, .month, .day], from: date)
    let normalized = cal.date(from: comps) ?? date

    let f = DateFormatter()
    f.calendar = cal
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: normalized)
}

private func readCache() -> HeatmapCacheLocal? {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
    let url = container.appendingPathComponent(cacheFileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }

    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(HeatmapCacheLocal.self, from: data)
    } catch {
        return nil
    }
}

private func makeRecentCounts(days: Int = 28) -> [Int] {
    let cache = readCache()
    var result: [Int] = []
    let now = Date()

    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!

    for offset in stride(from: days - 1, through: 0, by: -1) {
        if let day = cal.date(byAdding: .day, value: -offset, to: now) {
            let key = isoDayKey(day)
            let value = cache?.countsByDay[key] ?? 0
            result.append(value)
        }
    }
    return result
}

private func sampleCounts(_ days: Int = 28) -> [Int] {
    // Simple deterministic sample: cycle 0,1,2
    return (0..<days).map { $0 % 3 }
}

// MARK: - Timeline

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), counts: sampleCounts())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        let counts = makeRecentCounts()
        return SimpleEntry(date: Date(), configuration: configuration, counts: counts.isEmpty ? sampleCounts() : counts)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        var entries: [SimpleEntry] = []

        let currentDate = Date()
        for hourOffset in 0 ..< 5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            let counts = makeRecentCounts()
            let entry = SimpleEntry(date: entryDate, configuration: configuration, counts: counts.isEmpty ? sampleCounts() : counts)
            entries.append(entry)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let counts: [Int] // grid counts for recent days (e.g., 28 cells)
}

// MARK: - View

struct Habit_Tracker_WidgetEntryView: View {
    var entry: Provider.Entry

    private let palette = HeatmapPalette()

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Habits").font(.headline)
                Spacer()
                Text(entry.date, style: .time).font(.caption2).monospacedDigit()
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(entry.counts.indices, id: \.self) { idx in
                    let count = entry.counts[idx]
                    Rectangle()
                        .fill(squareFill(for: count))
                        .frame(height: 10)
                        .cornerRadius(2)
                        .accessibilityLabel("Day \(idx + 1), count \(count)")
                }
            }

            if !entry.configuration.favoriteEmoji.isEmpty {
                HStack(spacing: 4) {
                    Text("Fav:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.configuration.favoriteEmoji)
                }
            }
        }
        .padding(8)
        .containerBackground(.background, for: .widget)    }

    /// Widget currently stores `count` per day in the cache.
    /// For now we map it to a simple progress model:
    /// - 0 => empty
    /// - 1 => partial (started)
    /// - 2+ => complete
    ///
    /// Later: switch this to `completedRequired/totalRequired` coming from your widget payload.
    private func squareFill(for count: Int) -> Color {
        let base = Color.green // TODO: later pull from payload/habit

        if count <= 0 {
            return palette.empty
        } else {
            // MVP parity: any progress means "green"
            return palette.color(base: base, isComplete: true, hasRow: true)
        }
    }}

// MARK: - Widget

struct Habit_Tracker_Widget: Widget {
    let kind: String = "Habit_Tracker_Widget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            Habit_Tracker_WidgetEntryView(entry: entry)
        }
    }
}

// MARK: - Intent Defaults + Previews

extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "😀"
        return intent
    }

    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "🤩"
        return intent
    }
}

#Preview(as: .systemSmall) {
    Habit_Tracker_Widget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, counts: sampleCounts())
    SimpleEntry(date: .now, configuration: .starEyes, counts: sampleCounts())
}
