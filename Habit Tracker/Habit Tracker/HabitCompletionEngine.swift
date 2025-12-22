import Foundation
import CoreData
import EventKit

// MARK: - HabitCompletionEngine
// Goal:
// - Fetch reminders for today (include completed).
// - Build a "doneKeys" set using a stable reminder identifier.
// - For each Habit, fetch its required linked reminders (WITHOUT using habit.links).
// - Upsert a HabitCompletion for today and mark isComplete when all required are done.

enum HabitCompletionEngine {

    // MARK: Public API

    /// Call this after saving links OR on app start to sync today's habit completions.
    static func syncTodayFromReminders(in context: NSManagedObjectContext,
                                       includeCompleted: Bool = true) {
        Task {
            let store = EKEventStore()
            let ok = await requestRemindersAccessIfNeeded(store: store)
            guard ok else {
                print("✗ HabitCompletionEngine: no reminders access")
                return
            }

            let all = await fetchAllReminders(store: store)
            let todayReminders = filterToTodayRelevant(all, includeCompleted: includeCompleted)

            await MainActor.run {
                upsertCompletionsForToday(in: context, reminders: todayReminders)
            }
        }
    }

    // MARK: Core compute / upsert

    @MainActor
    static func upsertCompletionsForToday(in context: NSManagedObjectContext,
                                         reminders: [EKReminder]) {

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        // Build done key set (stable IDs) for completed reminders that are relevant to today
        let doneKeys: Set<String> = Set(
            reminders
                .filter { $0.isCompleted }
                .map { stableIdentifierToStore(for: $0) }
        )

        if let sample = doneKeys.first {
            print("✓ HabitCompletionEngine: sample done key = \(sample)")
        }
        print("✓ HabitCompletionEngine: completedKeys.count = \(doneKeys.count)")

        // Fetch habits
        let habits = fetchHabits(in: context)
        print("===== Core Data habits (sync) =====")
        for h in habits {
            let name = (h.valueIfExists(forKey: "name") as? String) ?? "?"
            let id = (h.value(forKey: "id") as? UUID)?.uuidString ?? "no-id"
            print(" - id: \(id), name: \(name)")
        }
        print("===== end =====")

        // Detect link entity name + relationship key from Link -> Habit
        guard let linkEntityName = guessLinkEntityName(in: context) else {
            print("✗ HabitCompletionEngine: could not guess link entity name (check Core Data model)")
            return
        }
        guard let linkToHabitKey = findRelationshipKey(entityName: linkEntityName,
                                                      destinationEntityName: "Habit",
                                                      in: context) else {
            print("✗ HabitCompletionEngine: could not find relationship from \(linkEntityName) -> Habit")
            return
        }

        // Upsert completion per habit
        for habit in habits {
            // Fetch required links for this habit (no habit.links access!)
            let requiredLinks = fetchLinks(for: habit,
                                           linkEntityName: linkEntityName,
                                           linkToHabitKey: linkToHabitKey,
                                           requiredOnly: true,
                                           in: context)

            var requiredDone = 0
            for link in requiredLinks {
                let linkKeys = linkStoredKeys(link)
                let matched = !linkKeys.intersection(doneKeys).isEmpty
                if matched { requiredDone += 1 }

                if let anyKey = linkKeys.first {
                    print("🔗 required link key=\(anyKey) matchedDone=\(matched)")
                } else {
                    print("🔗 required link key=<none> matchedDone=\(matched)")
                }
            }

            let requiredTotal = requiredLinks.count
            let isComplete = (requiredTotal > 0) && (requiredDone == requiredTotal)

            let habitName = (habit.valueIfExists(forKey: "name") as? String) ?? "?"
            print("📊 HabitCompletionEngine: habit '\(habitName)' required: \(requiredTotal) done today: \(requiredDone) isComplete: \(isComplete)")

            upsertHabitCompletion(habit: habit,
                                  startOfDay: startOfDay,
                                  endOfDay: endOfDay,
                                  requiredTotal: requiredTotal,
                                  requiredDone: requiredDone,
                                  isComplete: isComplete,
                                  in: context)
        }

        do {
            try context.save()
            print("✓ HabitCompletionEngine: saved completions for today.")
        } catch {
            print("✗ HabitCompletionEngine: failed saving completions: \(error)")
        }
    }

    // MARK: Upsert HabitCompletion

    @MainActor
    private static func upsertHabitCompletion(habit: NSManagedObject,
                                             startOfDay: Date,
                                             endOfDay: Date,
                                             requiredTotal: Int,
                                             requiredDone: Int,
                                             isComplete: Bool,
                                             in context: NSManagedObjectContext) {

        guard let completionEntity = context.persistentStoreCoordinator?.managedObjectModel.entitiesByName["HabitCompletion"]?.name else {
            // If your entity is NOT named HabitCompletion, update it here.
            print("✗ HabitCompletionEngine: missing entity HabitCompletion in model")
            return
        }

        // Find existing completion for habit+day (best-effort, using whatever relationship exists)
        let req = NSFetchRequest<NSManagedObject>(entityName: completionEntity)
        req.fetchLimit = 1

        // Try to find relationship key completion -> Habit
        let completionToHabitKey =
            findRelationshipKey(entityName: completionEntity,
                                destinationEntityName: "Habit",
                                in: context)

        var preds: [NSPredicate] = [
            NSPredicate(format: "date >= %@ AND date < %@", startOfDay as NSDate, endOfDay as NSDate)
        ]
        if let k = completionToHabitKey {
            preds.append(NSPredicate(format: "%K == %@", k, habit))
        }
        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)

        let completion: NSManagedObject
        if let existing = try? context.fetch(req).first {
            completion = existing
        } else {
            completion = NSEntityDescription.insertNewObject(forEntityName: completionEntity, into: context)
            completion.setIfExistsDate(startOfDay, forKey: "date")

            if let k = completionToHabitKey {
                completion.setIfExistsObject(habit, forKey: k)
            }
        }

        completion.setIfExistsInt(requiredTotal, forKey: "totalRequired")
        completion.setIfExistsInt(requiredDone, forKey: "completedRequired")
        completion.setIfExistsBool(isComplete, forKey: "isComplete")
    }

    // MARK: Fetch habits

    @MainActor
    private static func fetchHabits(in context: NSManagedObjectContext) -> [NSManagedObject] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Habit")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    // MARK: Fetch links (NO Habit.links)

    @MainActor
    private static func fetchLinks(for habit: NSManagedObject,
                                   linkEntityName: String,
                                   linkToHabitKey: String,
                                   requiredOnly: Bool,
                                   in context: NSManagedObjectContext) -> [NSManagedObject] {

        let req = NSFetchRequest<NSManagedObject>(entityName: linkEntityName)

        var preds: [NSPredicate] = [
            NSPredicate(format: "%K == %@", linkToHabitKey, habit)
        ]

        if requiredOnly {
            // Support either "isRequired" or "required" as a boolean field
            if context.entityHasAttribute(entityName: linkEntityName, attr: "isRequired") {
                preds.append(NSPredicate(format: "isRequired == YES"))
            } else if context.entityHasAttribute(entityName: linkEntityName, attr: "required") {
                preds.append(NSPredicate(format: "required == YES"))
            }
        }

        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        return (try? context.fetch(req)) ?? []
    }

    // MARK: Link stored keys (handle old + new fields)

    private static func linkStoredKeys(_ link: NSManagedObject) -> Set<String> {
        var keys = Set<String>()

        // common field names we’ve used across iterations:
        let candidates = [
            "reminderIdentifier",
            "reminderId",
            "reminderID",
            "calendarItemIdentifier",
            "calendarItemExternalIdentifier"
        ]

        for c in candidates {
            if let s = link.valueIfExists(forKey: c) as? String, !s.isEmpty {
                keys.insert(s)
            }
        }

        // some projects stored both "reminderId" and "reminderIdentifier" with same value;
        // intersection logic is fine with duplicates.
        return keys
    }

    // MARK: Reminder stable key

    private static func stableIdentifierToStore(for r: EKReminder) -> String {
        // Prefer external identifier (more stable for repeating reminders)
        if let ext = r.calendarItemExternalIdentifier, !ext.isEmpty { return ext }
        return r.calendarItemIdentifier
    }

    // MARK: EventKit fetch helpers

    private static func requestRemindersAccessIfNeeded(store: EKEventStore) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .authorized, .fullAccess:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                store.requestFullAccessToReminders { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private static func fetchAllReminders(store: EKEventStore) async -> [EKReminder] {
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)

        return await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: reminders ?? [])
            }
        }
    }

    private static func filterToTodayRelevant(_ all: [EKReminder],
                                             includeCompleted: Bool) -> [EKReminder] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        func isInToday(_ date: Date) -> Bool {
            (date >= startOfDay) && (date < endOfDay)
        }

        let today = all.filter { r in
            // Due today?
            if let due = r.dueDateComponents?.date, isInToday(due) {
                return includeCompleted ? true : !r.isCompleted
            }

            // Completed today (even if due isn't today)
            if includeCompleted,
               r.isCompleted,
               let cd = r.completionDate,
               isInToday(cd) {
                return true
            }

            return false
        }

        print("Reminders (due today): fetched \(today.count) item(s). includeCompleted=\(includeCompleted)")
        for r in today {
            print("DueToday debug:")
            print("  title=\(r.title)")
            print("  due=\(String(describing: r.dueDateComponents?.date))")
            print("  isCompleted=\(r.isCompleted)")
            print("  completionDate=\(String(describing: r.completionDate))")
            print("  id=\(stableIdentifierToStore(for: r))")
        }

        return today
    }

    // MARK: Model introspection

    private static func findRelationshipKey(entityName: String,
                                           destinationEntityName: String,
                                           in context: NSManagedObjectContext) -> String? {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { return nil }
        guard let entity = model.entitiesByName[entityName] else { return nil }

        for (name, rel) in entity.relationshipsByName {
            if rel.destinationEntity?.name == destinationEntityName {
                return name
            }
        }
        return nil
    }

    /// Try to guess which Core Data entity is your "link" entity.
    /// This avoids crashes like: "could not locate an entity named 'ReminderLink'".
    private static func guessLinkEntityName(in context: NSManagedObjectContext) -> String? {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { return nil }

        // First try common names
        let common = ["ReminderLink", "ReminderLinkEntity", "HabitReminderLink", "HabitLink", "ReminderLinkModel"]
        for name in common {
            if model.entitiesByName[name] != nil { return name }
        }

        // Then scan entities for tell-tale attributes
        for (name, entity) in model.entitiesByName {
            let attrs = Set(entity.attributesByName.keys)
            let looksLikeLink =
                attrs.contains("reminderIdentifier") ||
                attrs.contains("reminderId") ||
                attrs.contains("calendarItemIdentifier") ||
                attrs.contains("calendarItemExternalIdentifier")

            let hasHabitRel = entity.relationshipsByName.values.contains { $0.destinationEntity?.name == "Habit" }

            if looksLikeLink && hasHabitRel {
                return name
            }
        }

        return nil
    }
}

// MARK: - NSManagedObject helpers (safe KVC)

private extension NSManagedObject {
    func setIfExistsString(_ value: String, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsBool(_ value: Bool, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsInt(_ value: Int, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsDate(_ value: Date, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func setIfExistsObject(_ value: Any?, forKey key: String) {
        guard entity.relationshipsByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func valueIfExists(forKey key: String) -> Any? {
        if entity.attributesByName[key] != nil { return value(forKey: key) }
        if entity.relationshipsByName[key] != nil { return value(forKey: key) }
        return nil
    }
}

private extension NSManagedObjectContext {
    func entityHasAttribute(entityName: String, attr: String) -> Bool {
        guard let model = persistentStoreCoordinator?.managedObjectModel else { return false }
        return model.entitiesByName[entityName]?.attributesByName[attr] != nil
    }
}
