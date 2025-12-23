import Foundation
import CoreData
import EventKit

enum HabitCompletionEngine {

    // MARK: Public API

    static func syncTodayFromReminders(in context: NSManagedObjectContext,
                                       includeCompleted: Bool = true) {
        ReminderService.shared.requestAccessIfNeeded { ok in
            guard ok else {
                print("✗ HabitCompletionEngine: no reminders access")
                return
            }

            ReminderService.shared.fetchTodayReminders(includeCompleted: includeCompleted) { todayReminders in
                Task { @MainActor in
                    upsertCompletionsForToday(in: context, reminders: todayReminders)
                }
            }
        }
    }

    // MARK: Core compute / upsert

    @MainActor
    static func upsertCompletionsForToday(in context: NSManagedObjectContext,
                                         reminders: [EKReminder]) {

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        // ✅ Clean key sets
        // Primary: stamped UUIDs (what we want long-term)
        // Legacy: external/item IDs (for old links only)
        var doneStampUUIDs = Set<String>()
        var doneLegacyKeys = Set<String>()

        for r in reminders where r.isCompleted {
            if let stamp = stampedUUID(from: r) {
                doneStampUUIDs.insert(stamp)
            } else {
                // Only collect legacy keys if no stamp exists (keeps counts sane)
                if let ext = r.calendarItemExternalIdentifier, !ext.isEmpty {
                    doneLegacyKeys.insert(ext)
                }
                doneLegacyKeys.insert(r.calendarItemIdentifier)
            }
        }

        let doneKeysForMatching = doneStampUUIDs.union(doneLegacyKeys)

        if let sample = doneStampUUIDs.first {
            print("✓ HabitCompletionEngine: sample stamped done uuid = \(sample)")
        } else if let sampleLegacy = doneLegacyKeys.first {
            print("✓ HabitCompletionEngine: sample legacy done key = \(sampleLegacy)")
        }

        print("✓ HabitCompletionEngine: completedStampUUIDs.count = \(doneStampUUIDs.count)")
        print("✓ HabitCompletionEngine: completedLegacyKeys.count = \(doneLegacyKeys.count)")

        // Fetch habits
        let habits = fetchHabits(in: context)

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
            let requiredLinks = fetchLinks(for: habit,
                                           linkEntityName: linkEntityName,
                                           linkToHabitKey: linkToHabitKey,
                                           requiredOnly: true,
                                           in: context)

            var requiredDone = 0
            for link in requiredLinks {
                // Normalize stored keys so older "stamp:UUID" still matches "UUID"
                let linkKeys = linkStoredKeys(link).map(normalizeStoredKey)
                let matched = !Set(linkKeys).intersection(doneKeysForMatching).isEmpty
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

    // MARK: - Key helpers

    /// Extract our stamp: habitsquares://reminder-link/<uuid>
    private static func stampedUUID(from reminder: EKReminder) -> String? {
        guard let url = reminder.url else { return nil }
        guard url.scheme?.lowercased() == "habitsquares" else { return nil }
        guard url.host?.lowercased() == "reminder-link" else { return nil }

        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.isEmpty ? nil : raw
    }

    /// Normalize any legacy-prefixed stored keys like "stamp:<uuid>", "ext:<id>", "id:<id>"
    private static func normalizeStoredKey(_ key: String) -> String {
        // Only strip known prefixes
        if key.hasPrefix("stamp:") { return String(key.dropFirst("stamp:".count)) }
        if key.hasPrefix("ext:") { return String(key.dropFirst("ext:".count)) }
        if key.hasPrefix("id:") { return String(key.dropFirst("id:".count)) }
        return key
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
            print("✗ HabitCompletionEngine: missing entity HabitCompletion in model")
            return
        }

        let req = NSFetchRequest<NSManagedObject>(entityName: completionEntity)
        req.fetchLimit = 1

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
            if context.entityHasAttribute(entityName: linkEntityName, attr: "isRequired") {
                preds.append(NSPredicate(format: "isRequired == YES"))
            } else if context.entityHasAttribute(entityName: linkEntityName, attr: "required") {
                preds.append(NSPredicate(format: "required == YES"))
            }
        }

        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: preds)
        return (try? context.fetch(req)) ?? []
    }

    // MARK: Link stored keys

    private static func linkStoredKeys(_ link: NSManagedObject) -> [String] {
        var keys: [String] = []
        let candidates = [
            "reminderIdentifier",
            "reminderId",
            "reminderID",
            "calendarItemIdentifier",
            "calendarItemExternalIdentifier"
        ]

        for c in candidates {
            if let s = link.valueIfExists(forKey: c) as? String, !s.isEmpty {
                keys.append(s)
            }
        }
        return keys
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

    private static func guessLinkEntityName(in context: NSManagedObjectContext) -> String? {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { return nil }

        let common = ["ReminderLink", "ReminderLinkEntity", "HabitReminderLink", "HabitLink", "ReminderLinkModel"]
        for name in common {
            if model.entitiesByName[name] != nil { return name }
        }

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
