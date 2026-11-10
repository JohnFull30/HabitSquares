//
//  WidgetSharedStore.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/23/25.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetSharedStore {

    // ✅ Replace with your existing App Group id from Signing & Capabilities
    static let appGroupID = "group.pullerlabs.habitsquares"

    /// Must match your widget kind string (usually the Widget struct name)
    private static let widgetKind = "HabitSquaresWidget"

    // MARK: - URLs

    private static func url(for filename: String, directory: URL?) -> URL? {
        if let directory { return directory.appendingPathComponent(filename) }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }

    // MARK: - Widget refresh

    private static func notifyWidget() {
        #if canImport(WidgetKit)
        // Avoid trying to reload from inside the widget extension itself.
        if Bundle.main.bundlePath.hasSuffix(".appex") { return }
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }

    // MARK: - Habits index

    private static let habitsIndexFile = "habits_index.json"

    static func writeHabitsIndex(_ payload: WidgetHabitsIndexPayload, directory: URL? = nil) {
        write(payload, filename: habitsIndexFile, directory: directory)
    }

    static func readHabitsIndex(directory: URL? = nil) -> WidgetHabitsIndexPayload? {
        read(WidgetHabitsIndexPayload.self, filename: habitsIndexFile, directory: directory)
    }

    // MARK: - Per-habit today payload

    static func todayFileName(for habitID: String) -> String {
        // keep filenames safe-ish
        let safe = habitID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "today_\(safe).json"
    }

    static func writeToday(_ payload: WidgetHabitTodayPayload, directory: URL? = nil) {
        write(payload, filename: todayFileName(for: payload.habitID), directory: directory)
    }

    static func readToday(habitID: String, directory: URL? = nil) -> WidgetHabitTodayPayload? {
        // The index is authoritative. Orphaned files are retained but never displayed.
        guard let index = readHabitsIndex(directory: directory),
              index.habits.contains(where: { $0.id == habitID }),
              let payload = read(WidgetHabitTodayPayload.self,
                                 filename: todayFileName(for: habitID), directory: directory),
              payload.habitID == habitID else { return nil }
        return payload
    }

    static func currentSummary(_ payload: WidgetHabitTodayPayload, now: Date = Date(),
                               calendar: Calendar = .current) -> WidgetHabitTodayPayload? {
        calendar.isDate(payload.updatedAt, inSameDayAs: now) ? payload : nil
    }

    // MARK: - WidgetSnapshot (existing widget UI cache)

    private static let snapshotFile = "widget_snapshot.json"

    static func writeSnapshot(_ snapshot: WidgetSnapshot, directory: URL? = nil) {
        write(snapshot, filename: snapshotFile, directory: directory)
    }

    static func readSnapshot(directory: URL? = nil) -> WidgetSnapshot? {
        guard let index = readHabitsIndex(directory: directory),
              let snapshot = read(WidgetSnapshot.self, filename: snapshotFile, directory: directory),
              snapshot.totalHabits == index.habits.count else { return nil }
        return snapshot
    }

    // MARK: - Generic JSON helpers

    private static func write<T: Codable>(_ value: T, filename: String, directory: URL?) {
        guard let fileURL = url(for: filename, directory: directory) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL, options: [.atomic])
            if directory == nil { notifyWidget() }
        } catch {
            print("WidgetSharedStore.write error for \(filename):", error)
        }
    }

    private static func read<T: Codable>(_ type: T.Type, filename: String, directory: URL?) -> T? {
        guard let fileURL = url(for: filename, directory: directory) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
