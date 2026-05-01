import Foundation
import CoreData

/// Seeds demo habits and manages links between Habits and Apple Reminders.
struct HabitSeeder {

    enum SeedPattern: String, CaseIterable, Identifiable {
        case recent
        case random
        case spread
        case showcase

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recent:
                return "Recent"
            case .random:
                return "Random"
            case .spread:
                return "Spread"
            case .showcase:
                return "Showcase"
            }
        }
    }

    // MARK: - Public seeding API

    /// Ensure there is at least one demo habit in the store.
    /// Call this once on app launch (usually from PersistenceController or App).
    static func ensureDemoHabits(in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
        fetchRequest.fetchLimit = 1

        let existingCount = (try? context.count(for: fetchRequest)) ?? 0
        guard existingCount == 0 else {
            // Already seeded
            return
        }

        let demoHabit = Habit(context: context)
        demoHabit.id = UUID()
        demoHabit.name = "Code"

        do {
            try context.save()
            print("✅ HabitSeeder.ensureDemoHabits: seeded demo habit '\(demoHabit.name ?? "Habit")'")
        } catch {
            print("❌ HabitSeeder.ensureDemoHabits: failed to save demo habits: \(error)")
        }
    }

    // MARK: - Debug seeding (Completions)

    /// Backwards-compatible helper.
    /// Defaults to `.recent` so existing callers keep working the same way.
    static func seedCompletions(
        dayCount: Int,
        for habit: Habit,
        in context: NSManagedObjectContext,
        markComplete: Bool = true
    ) {
        seedCompletions(
            dayCount: dayCount,
            pattern: .recent,
            for: habit,
            in: context,
            markComplete: markComplete
        )
    }

    /// Seeds `HabitCompletion` rows for a single habit using a chosen visual pattern.
    ///
    /// - Parameters:
    ///   - dayCount: How many completed days to create.
    ///   - pattern: The visual shape of the seeded data.
    ///   - habit: The target habit.
    ///   - context: Core Data context.
    ///   - markComplete: Whether seeded rows should be complete.
    static func seedCompletions(
        dayCount: Int,
        pattern: SeedPattern,
        for habit: Habit,
        in context: NSManagedObjectContext,
        markComplete: Bool = true
    ) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Use a larger visible window so random/spread patterns have room to breathe.
        let visibleWindowDays = max(56, dayCount)
        let start = cal.date(byAdding: .day, value: -(visibleWindowDays - 1), to: today) ?? today
        let endExclusive = cal.date(byAdding: .day, value: 1, to: today) ?? today

        // 1) Delete existing completions in the visible window for this habit
        // so the seed is deterministic for screenshots/dev use.
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        fetch.predicate = NSPredicate(
            format: "habit == %@ AND date >= %@ AND date < %@",
            habit,
            start as NSDate,
            endExclusive as NSDate
        )

        if let existing = try? context.fetch(fetch) {
            existing.forEach { context.delete($0) }
        }

        let offsets = seededOffsets(
            visibleWindowDays: visibleWindowDays,
            dayCount: dayCount,
            pattern: pattern
        )

        for offset in offsets {
            guard let date = cal.date(byAdding: .day, value: offset, to: start) else { continue }
            let d0 = cal.startOfDay(for: date)

            let obj = NSEntityDescription.insertNewObject(
                forEntityName: "HabitCompletion",
                into: context
            )

            obj.setValue(d0, forKey: "date")

            let totalRequired: Int32 = 1
            obj.setValue(totalRequired, forKey: "totalRequired")
            obj.setValue(markComplete ? totalRequired : 0, forKey: "completedRequired")
            obj.setValue(markComplete, forKey: "isComplete")
            obj.setValue("seed", forKey: "source")
            obj.setValue(habit, forKey: "habit")
        }

        do {
            try context.save()
            print("✅ HabitSeeder.seedCompletions: seeded \(dayCount) day(s) with pattern '\(pattern.title)' for \(habit.name ?? "Habit")")
        } catch {
            print("❌ HabitSeeder.seedCompletions: save failed:", error)
        }
    }

    /// Backwards-compatible helper for the old “Code” habit.
    static func ensureCodeReminderLink(
        in context: NSManagedObjectContext,
        forReminderIdentifier identifier: String,
        reminderTitle: String
    ) {
        let habit = fetchOrCreateHabit(named: "Code", in: context)

        upsertLink(
            habit: habit,
            in: context,
            forReminderIdentifier: identifier,
            reminderTitle: reminderTitle
        )

        print("🔗 HabitSeeder.ensureCodeReminderLink: linked reminder '\(reminderTitle)' (\(identifier)) to habit '\(habit.name ?? "Code")'")
    }

    // MARK: - Generic link API (used by ReminderListView)

    /// Create or update a `HabitReminderLink` between a Habit and a specific
    /// Reminders identifier. This is what makes the reminder "count" for that habit.
    static func upsertLink(
        habit: Habit,
        in context: NSManagedObjectContext,
        forReminderIdentifier identifier: String,
        reminderTitle: String
    ) {
        // Look for an existing link between this habit and this reminder id
        let fetch: NSFetchRequest<HabitReminderLink> = HabitReminderLink.fetchRequest()
        fetch.predicate = NSPredicate(
            format: "habit == %@ AND reminderIdentifier == %@",
            habit,
            identifier
        )
        fetch.fetchLimit = 1

        let link: HabitReminderLink
        if let existing = (try? context.fetch(fetch))?.first {
            link = existing
        } else {
            link = HabitReminderLink(context: context)
            link.id = UUID()
            link.habit = habit
            link.reminderIdentifier = identifier
        }

        // Mark as required so it counts toward completion
        link.isRequired = true   // 🔑 this is what HabitCompletionEngine uses

        do {
            try context.save()
            print("✅ HabitSeeder.upsertLink: linked reminder '\(reminderTitle)' (\(identifier)) to habit '\(habit.name ?? "Habit")'")
        } catch {
            print("❌ HabitSeeder.upsertLink: failed to save link: \(error)")
        }
    }

    // MARK: - Private helpers

    private static func seededOffsets(
        visibleWindowDays: Int,
        dayCount: Int,
        pattern: SeedPattern
    ) -> [Int] {
        guard visibleWindowDays > 0 else { return [] }

        let cappedCount = max(0, min(dayCount, visibleWindowDays))
        guard cappedCount > 0 else { return [] }

        switch pattern {
        case .recent:
            let start = max(0, visibleWindowDays - cappedCount)
            return Array(start..<visibleWindowDays)
            
        case .showcase:
            // Screenshot-focused pattern:
            // force visible activity across the whole window, not just near today.
            let todayIndex = visibleWindowDays - 1

            if cappedCount == 1 {
                return [todayIndex]
            }

            // Fixed anchors spread across the whole visible range.
            // These percentages intentionally touch early, middle, and late parts.
            let anchorPercents: [Double] = [
                0.08, 0.18, 0.30, 0.42, 0.55, 0.68, 0.78, 0.88, 0.95, 1.0
            ]

            var chosen: [Int] = []

            for percent in anchorPercents.prefix(cappedCount) {
                let raw = Int(round(Double(todayIndex) * percent))
                let clamped = max(0, min(todayIndex, raw))
                if chosen.contains(clamped) == false {
                    chosen.append(clamped)
                }
            }

            // If deduping reduced the count, fill nearby gaps across the whole range.
            if chosen.count < cappedCount {
                let remaining = Array(Set(0...todayIndex).subtracting(chosen)).sorted()
                let needed = cappedCount - chosen.count

                if needed > 0 && !remaining.isEmpty {
                    let step = max(1, remaining.count / needed)
                    var index = 0
                    while chosen.count < cappedCount && index < remaining.count {
                        chosen.append(remaining[index])
                        index += step
                    }
                }
            }

            // Always include today for screenshot usefulness.
            if chosen.contains(todayIndex) == false {
                if chosen.count >= cappedCount, let last = chosen.last {
                    chosen.removeAll { $0 == last }
                }
                chosen.append(todayIndex)
            }

            return Array(Set(chosen)).sorted()

        case .random:
            // First force broad coverage by dividing the range into regions.
            let regionCount = min(cappedCount, 6)
            let regionSize = Double(visibleWindowDays) / Double(regionCount)

            var chosen = Set<Int>()

            for region in 0..<regionCount {
                let start = Int(floor(Double(region) * regionSize))
                let end = Int(floor(Double(region + 1) * regionSize))
                let safeStart = min(start, visibleWindowDays - 1)
                let safeEnd = max(safeStart + 1, min(end, visibleWindowDays))
                let options = Array(safeStart..<safeEnd)

                if let pick = options.randomElement() {
                    chosen.insert(pick)
                }
            }

            // Fill the remaining slots randomly across the full range.
            var remainingPool = Array(Set(0..<visibleWindowDays).subtracting(chosen))
            remainingPool.shuffle()

            for value in remainingPool.prefix(max(0, cappedCount - chosen.count)) {
                chosen.insert(value)
            }

            // Mild bias toward today for screenshot usefulness.
            let todayIndex = visibleWindowDays - 1
            if cappedCount >= 3 && chosen.contains(todayIndex) == false {
                if let earliest = chosen.min() {
                    chosen.remove(earliest)
                    chosen.insert(todayIndex)
                }
            }

            return chosen.sorted()

        case .spread:
            // Stronger bucket-based spread that intentionally spans the whole range.
            if cappedCount == 1 {
                return [visibleWindowDays - 1]
            }

            var chosen: [Int] = []
            let bucketSize = Double(visibleWindowDays) / Double(cappedCount)

            for i in 0..<cappedCount {
                let rawStart = Double(i) * bucketSize
                let rawEnd = Double(i + 1) * bucketSize

                let start = Int(floor(rawStart))
                let end = Int(ceil(rawEnd))

                let safeStart = min(start, visibleWindowDays - 1)
                let safeEnd = max(safeStart + 1, min(end, visibleWindowDays))

                let options = Array(safeStart..<safeEnd)

                // Prefer center-ish positions within each bucket so the result reads cleaner.
                if options.count == 1 {
                    chosen.append(options[0])
                } else {
                    let mid = options.count / 2
                    let nearby = [mid, max(0, mid - 1), min(options.count - 1, mid + 1)]
                    if let pick = nearby.compactMap({ idx in
                        options.indices.contains(idx) ? options[idx] : nil
                    }).randomElement() {
                        chosen.append(pick)
                    }
                }
            }
            
            

            // Deduplicate while preserving order.
            var deduped: [Int] = []
            for value in chosen where deduped.contains(value) == false {
                deduped.append(value)
            }

            // Backfill any missing spots with evenly spaced extras.
            if deduped.count < cappedCount {
                let remaining = Array(Set(0..<visibleWindowDays).subtracting(deduped)).sorted()
                let needed = cappedCount - deduped.count

                if needed > 0 && !remaining.isEmpty {
                    let stride = max(1, remaining.count / needed)
                    var index = 0
                    while deduped.count < cappedCount && index < remaining.count {
                        deduped.append(remaining[index])
                        index += stride
                    }
                }
            }

            return Array(Set(deduped)).sorted()
        }
    }

    /// Fetch an existing habit with the given name or create it if missing.
    private static func fetchOrCreateHabit(
        named name: String,
        in context: NSManagedObjectContext
    ) -> Habit {
        let fetchRequest: NSFetchRequest<Habit> = Habit.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "name == %@", name)
        fetchRequest.fetchLimit = 1

        if let existing = (try? context.fetch(fetchRequest))?.first {
            print("✏️ HabitSeeder.fetchOrCreateHabit: reusing existing habit id=\(existing.objectID) name='\(existing.name ?? "<nil>")' for name='\(name)'")
            return existing
        }

        let habit = Habit(context: context)
        habit.id = UUID()
        habit.name = name
        habit.createdAt = Date()

        print("✏️ HabitSeeder.fetchOrCreateHabit: creating NEW habit id=\(habit.objectID) name='\(name)'")

        do {
            try context.save()
            print("✅ HabitSeeder.fetchOrCreateHabit: saved new habit id=\(habit.objectID) name='\(habit.name ?? "<nil>")'")
        } catch {
            print("❌ HabitSeeder.fetchOrCreateHabit: failed to save new habit '\(name)': \(error)")
        }

        return habit
    }
}
