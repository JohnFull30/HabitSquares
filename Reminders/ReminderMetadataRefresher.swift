import Foundation
import CoreData
import EventKit

final class ReminderMetadataRefresher {
    static let shared = ReminderMetadataRefresher()

    private init() {}

    @MainActor
    func refreshLinkTitles(in context: NSManagedObjectContext) async {
        print("🚀 ReminderMetadataRefresher: refreshLinkTitles started")

        let store = EKEventStore()
        let accessGranted = await requestAccessIfNeeded(store: store)

        guard accessGranted else {
            print("✗ ReminderMetadataRefresher: no reminders access")
            return
        }

        guard let linkEntityName = guessLinkEntityName(in: context) else {
            print("✗ ReminderMetadataRefresher: could not guess link entity name")
            return
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: linkEntityName)

        do {
            let links = try context.fetch(request)
            print("📦 ReminderMetadataRefresher: fetched \(links.count) link(s)")
            guard !links.isEmpty else { return }

            let reminders = await fetchAllReminders(from: store)
            print("🗂️ ReminderMetadataRefresher: fetched \(reminders.count) reminder(s) from EventKit")

            var changedCount = 0

            for link in links {
                let storedTitle = ((link.valueIfExists(forKey: "title") as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let reminderIdentifier = ((link.valueIfExists(forKey: "reminderIdentifier") as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let calendarItemIdentifier = ((link.valueIfExists(forKey: "calendarItemIdentifier") as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let calendarItemExternalIdentifier = ((link.valueIfExists(forKey: "calendarItemExternalIdentifier") as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard let reminder = findReminder(
                    for: link,
                    in: reminders
                ) else {
                    print("""
                    ⚠️ ReminderMetadataRefresher: could not resolve link
                       cachedTitle=\(storedTitle)
                       reminderIdentifier=\(reminderIdentifier)
                       calendarItemIdentifier=\(calendarItemIdentifier)
                       calendarItemExternalIdentifier=\(calendarItemExternalIdentifier)
                    """)
                    continue
                }

                let eventKitTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)

                print("""
                🔎 ReminderMetadataRefresher compare
                   cachedTitle=\(storedTitle)
                   eventKitTitle=\(eventKitTitle)
                   reminderStampedUUID=\(stampedUUID(from: reminder) ?? "")
                   reminder.calendarItemIdentifier=\(reminder.calendarItemIdentifier)
                   reminder.calendarItemExternalIdentifier=\(reminder.calendarItemExternalIdentifier)
                   stored reminderIdentifier=\(reminderIdentifier)
                   stored calendarItemIdentifier=\(calendarItemIdentifier)
                   stored calendarItemExternalIdentifier=\(calendarItemExternalIdentifier)
                """)

                guard !eventKitTitle.isEmpty else { continue }

                if eventKitTitle != storedTitle {
                    link.setIfExistsString(eventKitTitle, forKey: "title")
                    changedCount += 1
                    print("✏️ ReminderMetadataRefresher: updated cached title '\(storedTitle)' -> '\(eventKitTitle)'")
                }
            }

            if changedCount > 0, context.hasChanges {
                try context.save()
                print("✅ ReminderMetadataRefresher: saved \(changedCount) refreshed title(s)")
            } else {
                print("ℹ️ ReminderMetadataRefresher: no title changes needed")
            }

        } catch {
            print("❌ ReminderMetadataRefresher.refreshLinkTitles error: \(error)")
        }
    }

    // MARK: - Resolution

    private func findReminder(
        for link: NSManagedObject,
        in reminders: [EKReminder]
    ) -> EKReminder? {
        let storedStamp = firstNonEmptyString(link.valueIfExists(forKey: "reminderIdentifier"))
        let storedItemID = firstNonEmptyString(link.valueIfExists(forKey: "calendarItemIdentifier"))
        let storedExternalID = firstNonEmptyString(link.valueIfExists(forKey: "calendarItemExternalIdentifier"))

        for reminder in reminders {
            let reminderStamp = stampedUUID(from: reminder)
            let reminderItemID = reminder.calendarItemIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let reminderExternalID = reminder.calendarItemExternalIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

            if let storedStamp, let reminderStamp, storedStamp == reminderStamp {
                print("✅ ReminderMetadataRefresher: matched by stamped UUID")
                return reminder
            }

            if let storedItemID, !storedItemID.isEmpty, storedItemID == reminderItemID {
                print("✅ ReminderMetadataRefresher: matched by calendarItemIdentifier")
                return reminder
            }

            if let storedExternalID, !storedExternalID.isEmpty, storedExternalID == reminderExternalID {
                print("✅ ReminderMetadataRefresher: matched by calendarItemExternalIdentifier")
                return reminder
            }
        }

        return nil
    }

    private func stampedUUID(from reminder: EKReminder) -> String? {
        guard let url = reminder.url else { return nil }
        guard url.scheme?.lowercased() == "habitsquares" else { return nil }
        guard url.host?.lowercased() == "reminder-link" else { return nil }

        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.isEmpty ? nil : raw
    }

    private func fetchAllReminders(from store: EKEventStore) async -> [EKReminder] {
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)

        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func firstNonEmptyString(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Model helpers

    private func guessLinkEntityName(in context: NSManagedObjectContext) -> String? {
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

    // MARK: - Permissions

    private func requestAccessIfNeeded(store: EKEventStore) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .authorized, .fullAccess:
            return true

        case .notDetermined:
            return await withCheckedContinuation { continuation in
                if #available(iOS 17.0, *) {
                    store.requestFullAccessToReminders { granted, _ in
                        continuation.resume(returning: granted)
                    }
                } else {
                    store.requestAccess(to: .reminder) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }

        case .writeOnly, .denied, .restricted:
            return false

        @unknown default:
            return false
        }
    }
}

// MARK: - Safe KVC helpers

private extension NSManagedObject {
    func setIfExistsString(_ value: String, forKey key: String) {
        guard entity.attributesByName[key] != nil else { return }
        setValue(value, forKey: key)
    }

    func valueIfExists(forKey key: String) -> Any? {
        if entity.attributesByName[key] != nil { return value(forKey: key) }
        if entity.relationshipsByName[key] != nil { return value(forKey: key) }
        return nil
    }
}
