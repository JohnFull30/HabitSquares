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

    private static func url(for filename: String) -> URL? {
        FileManager.default
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

    static func writeHabitsIndex(_ payload: WidgetHabitsIndexPayload) {
        write(payload, filename: habitsIndexFile)
    }

    static func readHabitsIndex() -> WidgetHabitsIndexPayload? {
        read(WidgetHabitsIndexPayload.self, filename: habitsIndexFile)
    }

    // MARK: - Per-habit today payload

    static func todayFileName(for habitID: String) -> String {
        // keep filenames safe-ish
        let safe = habitID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return "today_\(safe).json"
    }

    static func writeToday(_ payload: WidgetHabitTodayPayload) {
        write(payload, filename: todayFileName(for: payload.habitID))
    }

    static func readToday(habitID: String) -> WidgetHabitTodayPayload? {
        read(WidgetHabitTodayPayload.self, filename: todayFileName(for: habitID))
    }

    // MARK: - WidgetSnapshot (existing widget UI cache)

    private static let snapshotFile = "widget_snapshot.json"

    static func writeSnapshot(_ snapshot: WidgetSnapshot) {
        write(snapshot, filename: snapshotFile)
    }

    static func readSnapshot() -> WidgetSnapshot? {
        read(WidgetSnapshot.self, filename: snapshotFile)
    }

    // MARK: - Generic JSON helpers

    private static func write<T: Codable>(_ value: T, filename: String) {
        guard let fileURL = url(for: filename) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL, options: [.atomic])
            notifyWidget()
        } catch {
            print("WidgetSharedStore.write error for \(filename):", error)
        }
    }

    private static func read<T: Codable>(_ type: T.Type, filename: String) -> T? {
        guard let fileURL = url(for: filename) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}
