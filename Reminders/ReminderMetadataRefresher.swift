//
//  ReminderMetadataRefresher.swift
//  Habit Tracker
//
//  Created by John Fuller on 3/22/26.
//


import Foundation
import CoreData
import EventKit

final class ReminderMetadataRefresher {
    static let shared = ReminderMetadataRefresher()

    private init() {}

    @MainActor
    func refreshLinkTitles(in context: NSManagedObjectContext) async {
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
            guard !links.isEmpty else { return }

            var changedCount = 0

            for link in links {
                guard let reminder = findReminder(for: link, in: store) else { continue }

                let eventKitTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let cachedTitle = ((link.valueIfExists(forKey: "title") as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !eventKitTitle.isEmpty else { continue }

                if eventKitTitle != cachedTitle {
                    link.setIfExistsString(eventKitTitle, forKey: "title")
                    changedCount += 1
                    print("✏️ ReminderMetadataRefresher: updated cached title '\(cachedTitle)' -> '\(eventKitTitle)'")
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

    // MARK: - Reminder resolution

    private func findReminder(for link: NSManagedObject, in store: EKEventStore) -> EKReminder? {
        let ids = orderedCandidateIDs(from: link)

        for id in ids {
            if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
                return reminder
            }
        }

        return nil
    }

    private func orderedCandidateIDs(from link: NSManagedObject) -> [String] {
        var ids: [String] = []

        func append(_ raw: Any?) {
            guard let value = raw as? String else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !ids.contains(trimmed) else { return }
            ids.append(trimmed)
        }

        // Priority order based on your current storage
        append(link.valueIfExists(forKey: "reminderIdentifier"))
        append(link.valueIfExists(forKey: "reminderId"))
        append(link.valueIfExists(forKey: "reminderID"))
        append(link.valueIfExists(forKey: "calendarItemIdentifier"))
        append(link.valueIfExists(forKey: "calendarItemExternalIdentifier"))

        return ids
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