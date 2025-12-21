import Foundation
import CoreData
import EventKit

// MARK: - HabitCompletionEngine
enum HabitCompletionEngine {

    @MainActor
    static func upsertCompletionsForToday(
        in context: NSManagedObjectContext,
        reminders: [EKReminder]
    ) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Build an index of "completed today" reminders for matching
        let completedIndex = CompletedReminderIndex(reminders: reminders)

        print("✅ HabitCompletionEngine: completed identifiers = \(Array(completedIndex.ids))")
        print("✅ HabitCompletionEngine: completed externalIds   = \(Array(completedIndex.externalIds))")
        print("✅ HabitCompletionEngine: completed titleKeys     = \(Array(completedIndex.titleKeys).prefix(8)) ...")

        let habits: [Habit] = fetchAllHabits(in: context)
        let allLinks: [NSManagedObject] = fetchAllLinks(in: context)

        for habit in habits {
            let habitName = habit.name ?? "<unnamed>"

            let linksForHabit = allLinks.filter { link in
                guard let linkedHabitID = link.linkedHabitObjectID() else { return false }
                return linkedHabitID == habit.objectID
            }

            let requiredLinks = linksForHabit.filter {
                $0.boolValue(forAnyKey: ["isRequired", "required", "is_required"]) == true
            }

            let requiredCount = requiredLinks.count

            let completedRequiredCount = requiredLinks.reduce(into: 0) { partial, link in
                let linkReminderID = link.anyStringValue(forAnyKey: [
                    "reminderID", "reminderId",
                    "reminderIdentifier", "ekReminderID",
                    "calendarItemIdentifier", "externalIdentifier"
                ])

                let linkTitle = link.anyStringValue(forAnyKey: [
                    "title", "reminderTitle", "reminderName", "name"
                ])

                let linkCalendarTitle = link.anyStringValue(forAnyKey: [
                    "calendarTitle", "listTitle", "reminderListTitle"
                ])

                let matched = completedIndex.matches(
                    reminderID: linkReminderID,
                    title: linkTitle,
                    calendarTitle: linkCalendarTitle
                )

                // Helpful log so we can see WHY it isn't matching
                print("🔗 required link → id=\(linkReminderID ?? "nil") title=\(linkTitle ?? "nil") cal=\(linkCalendarTitle ?? "nil") matchedDone=\(matched)")

                if matched { partial += 1 }
            }

            // If required == 0, treat as NOT complete (prevents auto-green)
            let isComplete = (requiredCount > 0) && (completedRequiredCount == requiredCount)

            print("""
            📊 HabitCompletionEngine: habit '\(habitName)'
              required: \(requiredCount)
              done today: \(completedRequiredCount)
              isComplete: \(isComplete)
            """)

            upsertCompletionRow(
                in: context,
                habit: habit,
                date: today,
                totalRequired: requiredCount,
                completedRequired: completedRequiredCount,
                isComplete: isComplete,
                source: "reminders"
            )
        }

        do {
            if context.hasChanges {
                try context.save()
            }
            print("✅ HabitCompletionEngine: saved completions for today.")
        } catch {
            print("❌ HabitCompletionEngine: failed saving completions: \(error)")
        }
    }
}

// MARK: - CompletedReminderIndex (match by id first, then title+calendar)
private struct CompletedReminderIndex {
    let ids: Set<String>
    let externalIds: Set<String>
    let titleKeys: Set<String>
    let titleOnly: Set<String>

    init(reminders: [EKReminder]) {
        var ids = Set<String>()
        var external = Set<String>()
        var titleKeys = Set<String>()
        var titleOnly = Set<String>()

        for r in reminders where r.isCompleted {
            ids.insert(Self.norm(r.calendarItemIdentifier))
            if let ext = r.calendarItemExternalIdentifier {
                external.insert(Self.norm(ext))
            }

            let t = (r.title).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                titleOnly.insert(Self.norm(t))
                let calTitle = r.calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !calTitle.isEmpty {
                    titleKeys.insert(Self.makeTitleKey(title: t, calendarTitle: calTitle))
                }
            }
        }

        self.ids = ids
        self.externalIds = external
        self.titleKeys = titleKeys
        self.titleOnly = titleOnly
    }

    func matches(reminderID: String?, title: String?, calendarTitle: String?) -> Bool {
        // 1) Strong match: identifier/externalIdentifier
        if let reminderID {
            let nid = Self.norm(reminderID)
            if ids.contains(nid) || externalIds.contains(nid) {
                return true
            }
        }

        // 2) Fallback (repeating reminders): title + calendar title
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let calendarTitle, !calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if titleKeys.contains(Self.makeTitleKey(title: title, calendarTitle: calendarTitle)) {
                    return true
                }
            }
            // 3) Last resort: title only (works but can collide if duplicates)
            if titleOnly.contains(Self.norm(title)) {
                return true
            }
        }

        return false
    }

    private static func makeTitleKey(title: String, calendarTitle: String) -> String {
        "\(norm(title))|\(norm(calendarTitle))"
    }

    private static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Core Data helpers
private extension HabitCompletionEngine {

    @MainActor
    static func fetchAllHabits(in context: NSManagedObjectContext) -> [Habit] {
        let req = NSFetchRequest<Habit>(entityName: "Habit")
        req.returnsObjectsAsFaults = false
        do { return try context.fetch(req) }
        catch {
            print("❌ HabitCompletionEngine: failed to fetch habits: \(error)")
            return []
        }
    }

    @MainActor
    static func fetchAllLinks(in context: NSManagedObjectContext) -> [NSManagedObject] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "HabitReminderLink")
        req.returnsObjectsAsFaults = false
        do { return try context.fetch(req) }
        catch {
            print("❌ HabitCompletionEngine: failed to fetch HabitReminderLink: \(error)")
            return []
        }
    }

    @MainActor
    static func upsertCompletionRow(
        in context: NSManagedObjectContext,
        habit: Habit,
        date: Date,
        totalRequired: Int,
        completedRequired: Int,
        isComplete: Bool,
        source: String
    ) {
        guard
            let model = context.persistentStoreCoordinator?.managedObjectModel,
            let completionEntity = model.entitiesByName["HabitCompletion"]
        else {
            print("❌ HabitCompletionEngine: missing entity 'HabitCompletion' in model. Check your Core Data entity name.")
            return
        }

        let req = NSFetchRequest<NSManagedObject>(entityName: "HabitCompletion")
        req.fetchLimit = 1

        let habitKey = "habit"
        let dateKey = "date"

        if completionEntity.relationshipsByName[habitKey] != nil,
           completionEntity.attributesByName[dateKey] != nil {
            req.predicate = NSPredicate(format: "%K == %@ AND %K == %@", habitKey, habit, dateKey, date as NSDate)
        }

        do {
            let existing = try context.fetch(req).first
            let completion = existing ?? NSManagedObject(entity: completionEntity, insertInto: context)

            if completionEntity.relationshipsByName[habitKey] != nil {
                completion.setValue(habit, forKey: habitKey)
            }

            completion.setIfExists(date, forKey: "date")
            completion.setIfExists(Int64(totalRequired), forKey: "totalRequired")
            completion.setIfExists(Int64(completedRequired), forKey: "completedRequired")
            completion.setIfExists(isComplete, forKey: "isComplete")
            completion.setIfExists(source, forKey: "source")

        } catch {
            print("❌ HabitCompletionEngine: failed upserting HabitCompletion: \(error)")
        }
    }
}

// MARK: - NSManagedObject safe access helpers
private extension NSManagedObject {

    func hasAttribute(_ key: String) -> Bool {
        entity.attributesByName[key] != nil
    }

    func hasRelationship(_ key: String) -> Bool {
        entity.relationshipsByName[key] != nil
    }

    // Reads String OR UUID-ish values and returns a String.
    func anyStringValue(forAnyKey keys: [String]) -> String? {
        for k in keys where hasAttribute(k) {
            let v = value(forKey: k)
            if let s = v as? String { return s }
            if let u = v as? UUID { return u.uuidString }
            if let n = v as? NSUUID { return n.uuidString }
        }
        return nil
    }

    func boolValue(forAnyKey keys: [String]) -> Bool? {
        for k in keys where hasAttribute(k) {
            if let v = value(forKey: k) as? Bool { return v }
            if let v = value(forKey: k) as? NSNumber { return v.boolValue }
        }
        return nil
    }

    func linkedHabitObjectID() -> NSManagedObjectID? {
        let candidateKeys = ["habit", "parentHabit", "ownerHabit"]
        for k in candidateKeys where hasRelationship(k) {
            if let h = value(forKey: k) as? NSManagedObject {
                return h.objectID
            }
        }
        return nil
    }

    func setIfExists(_ value: Any?, forKey key: String) {
        guard hasAttribute(key) else { return }
        setValue(value, forKey: key)
    }
}
