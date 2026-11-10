import XCTest
import CoreData
import EventKit
@testable import habitSqaures

@MainActor
final class Habit_TrackerTests: XCTestCase {
    private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!

    private func context() -> NSManagedObjectContext {
        // Share the production model instance to avoid ambiguous generated-class lookup
        // when several fixture containers coexist with the running test host.
        let container = NSPersistentContainer(name: "HabitModel",
            managedObjectModel: PersistenceController.shared.container.managedObjectModel)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in precondition(error == nil) }
        return container.viewContext
    }

    private func habit(in context: NSManagedObjectContext, name: String = "Keep me") -> Habit {
        let habit = Habit(context: context)
        habit.id = UUID()
        habit.name = name
        habit.createdAt = now
        return habit
    }

    private func link(_ habit: Habit, key: String = "stamp:linked", required: Bool = true,
                      in context: NSManagedObjectContext) -> HabitReminderLink {
        let link = HabitReminderLink(context: context)
        link.id = UUID()
        link.habit = habit
        link.reminderIdentifier = key
        link.isRequired = required
        return link
    }

    private func row(_ habit: Habit, daysAgo: Int, source: String? = nil,
                     complete: Bool = true, in context: NSManagedObjectContext) -> HabitCompletion {
        let row = HabitCompletion(context: context)
        row.id = UUID()
        row.habit = habit
        row.date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)
        row.source = source
        row.isComplete = complete
        row.totalRequired = 3
        row.completedRequired = complete ? 3 : 1
        return row
    }

    private func reminder(completed: Bool = true, key: String = "linked") -> EKReminder {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Read"
        reminder.url = URL(string: "habitsquares://reminder-link/\(key)")
        reminder.isCompleted = completed
        reminder.completionDate = completed ? now : nil
        return reminder
    }

    func testBackfillNeverRewritesExistingHistoryOrProvenance() throws {
        let context = context()
        let habit = habit(in: context)
        _ = link(habit, in: context)
        let sources: [String?] = [nil, "manual", "seed", HabitCompletionEngine.liveSource, HabitCompletionEngine.historySource]
        let rows = sources.enumerated().map { row(habit, daysAgo: $0.offset + 1, source: $0.element,
                                                   complete: $0.offset % 2 == 0, in: context) }
        try context.save()
        let before = rows.map { ($0.objectID, $0.date, $0.source, $0.totalRequired, $0.completedRequired, $0.isComplete) }
        // Positive evidence that contradicts a stored partial day must not rewrite it either.
        let yesterday = Calendar.current.startOfDay(for: rows[1].date!)
        try HabitCompletionEngine.backfillHistory(in: context, doneKeysByDay: [yesterday: ["linked"]], now: now)
        for (row, old) in zip(rows, before) {
            XCTAssertEqual(row.objectID, old.0)
            XCTAssertEqual(row.date, old.1)
            XCTAssertEqual(row.source, old.2)
            XCTAssertEqual(row.totalRequired, old.3)
            XCTAssertEqual(row.completedRequired, old.4)
            XCTAssertEqual(row.isComplete, old.5)
        }
        XCTAssertEqual(try context.count(for: HabitCompletion.fetchRequest()), rows.count)
    }

    func testBackfillImportsPositiveEvidenceOnceAndSkipsTodayAndEmptyDays() throws {
        let context = context()
        let habit = habit(in: context)
        _ = link(habit, in: context)
        let yesterday = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: now)!)
        let emptyDay = Calendar.current.date(byAdding: .day, value: -1, to: yesterday)!
        let evidence: [Date: Set<String>] = [yesterday: ["linked"], emptyDay: [], now: ["linked"]]
        try HabitCompletionEngine.backfillHistory(in: context, doneKeysByDay: evidence, now: now)
        try HabitCompletionEngine.backfillHistory(in: context, doneKeysByDay: evidence, now: now)
        let rows = try context.fetch(HabitCompletion.fetchRequest())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.date, yesterday)
        XCTAssertEqual(rows.first?.source, HabitCompletionEngine.historySource)
        XCTAssertEqual(rows.first?.completedRequired, 1)
        XCTAssertEqual(rows.first?.isComplete, true)
    }

    func testUnlinkingOrMissingRemindersCannotClearHistoryOrToday() throws {
        let context = context()
        let habit = habit(in: context)
        let link = link(habit, in: context)
        let past = row(habit, daysAgo: 1, source: HabitCompletionEngine.liveSource, in: context)
        let today = row(habit, daysAgo: 0, source: HabitCompletionEngine.liveSource, in: context)
        try context.save()
        try HabitCompletionEngine.updateToday(in: context, reminders: [], now: now)
        XCTAssertTrue(today.isComplete)
        context.delete(link)
        try context.save()
        try HabitCompletionEngine.backfillHistory(in: context, doneKeysByDay: [:], now: now)
        try HabitCompletionEngine.updateToday(in: context, reminders: [], now: now)
        XCTAssertTrue(past.isComplete)
        XCTAssertTrue(today.isComplete)
        XCTAssertEqual(today.totalRequired, 3)
    }

    func testLiveTodayCanCompleteAndUncompleteWithoutChangingYesterday() throws {
        let context = context()
        let habit = habit(in: context)
        _ = link(habit, in: context)
        let past = row(habit, daysAgo: 1, in: context)
        let reminder = reminder()
        try HabitCompletionEngine.updateToday(in: context, reminders: [reminder], now: now)
        var today = try context.fetch(HabitCompletion.fetchRequest()).first { $0 !== past }
        XCTAssertEqual(today?.isComplete, true)
        XCTAssertEqual(today?.source, HabitCompletionEngine.liveSource)
        reminder.isCompleted = false
        reminder.completionDate = nil
        try HabitCompletionEngine.updateToday(in: context, reminders: [reminder], now: now)
        today = try context.fetch(HabitCompletion.fetchRequest()).first { $0 !== past }
        XCTAssertEqual(today?.isComplete, false)
        XCTAssertTrue(past.isComplete)
        XCTAssertEqual(past.totalRequired, 3)
    }

    func testLegacyAndManualTodayRowsArePreserved() throws {
        for source in [nil, "manual", "seed"] as [String?] {
            let context = context()
            let habit = habit(in: context)
            _ = link(habit, in: context)
            let today = row(habit, daysAgo: 0, source: source, in: context)
            try context.save()
            try HabitCompletionEngine.updateToday(in: context, reminders: [reminder(completed: false)], now: now)
            XCTAssertTrue(today.isComplete)
            XCTAssertEqual(today.source, source)
            XCTAssertEqual(today.totalRequired, 3)
        }
    }

    func testUnresolvedRequiredLinkPreventsPartialFetchFromClearingToday() throws {
        let context = context()
        let habit = habit(in: context)
        _ = link(habit, in: context)
        _ = link(habit, key: "missing", in: context)
        let today = row(habit, daysAgo: 0, source: HabitCompletionEngine.liveSource, in: context)
        try context.save()
        try HabitCompletionEngine.updateToday(in: context, reminders: [reminder(completed: false)], now: now)
        XCTAssertTrue(today.isComplete)
        XCTAssertEqual(today.completedRequired, 3)
    }

    func testLinkPopulationPreservesReminderURLNotesRecurrenceAndSchedule() throws {
        let context = context()
        let habit = habit(in: context)
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Original title"
        reminder.notes = "Original notes including a link https://example.com"
        reminder.url = URL(string: "https://example.com/original?keep=1")
        reminder.dueDateComponents = DateComponents(year: 2026, month: 11, day: 10, hour: 9)
        reminder.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)]
        reminder.priority = 5
        let originalURL = reminder.url
        let originalDue = reminder.dueDateComponents
        let linked = HabitReminderLink(context: context)
        linked.habit = habit
        ReminderLinkIdentity.populate(linked, from: reminder, required: true)
        try context.save()
        XCTAssertEqual(reminder.url, originalURL)
        XCTAssertEqual(reminder.notes, "Original notes including a link https://example.com")
        XCTAssertEqual(reminder.title, "Original title")
        XCTAssertEqual(reminder.dueDateComponents, originalDue)
        XCTAssertEqual(reminder.recurrenceRules?.first?.frequency, .weekly)
        XCTAssertEqual(reminder.recurrenceRules?.first?.interval, 2)
        XCTAssertEqual(reminder.priority, 5)
        XCTAssertEqual(linked.title, "Original title")
        XCTAssertTrue(linked.isRequired)
        XCTAssertNotNil(linked.id)
    }

    func testLinkIdentityDoesNotStampAnEmptyURLAndKeepsExistingStamp() throws {
        let reminder = EKReminder(eventStore: EKEventStore())
        _ = ReminderLinkIdentity.identifier(for: reminder)
        XCTAssertNil(reminder.url)
        reminder.url = URL(string: "habitsquares://reminder-link/old-stamp")
        XCTAssertEqual(ReminderLinkIdentity.identifier(for: reminder), "old-stamp")
        XCTAssertEqual(reminder.url?.absoluteString, "habitsquares://reminder-link/old-stamp")
    }

    func testLegacyLinkAliasesAndMissingKeysAreSafe() throws {
        let context = context()
        let habit = habit(in: context)
        let link = HabitReminderLink(context: context)
        link.habit = habit
        XCTAssertTrue(ReminderLinkIdentity.storedKeys(link).isEmpty) // Previously undefined-key crash.
        link.ekReminderID = "id:legacy-item"
        link.reminderKey = "ext:legacy-external"
        XCTAssertEqual(ReminderLinkIdentity.storedKeys(link), ["legacy-item", "legacy-external"])
        link.reminderIdentifier = "stamp:linked"
        XCTAssertTrue(ReminderLinkIdentity.matches(reminder(), link: link))
        XCTAssertTrue(ReminderLinkIdentity.storedKeys(link).contains("legacy-item"))
    }

    func testSQLiteReopenPreservesHabitIDsHistoryAndLegacyLinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Disposable fixture only; no production store is opened or migrated.
        let url = directory.appendingPathComponent("HabitModel.sqlite")
        let model = PersistenceController.shared.container.managedObjectModel
        func open() throws -> NSPersistentContainer {
            let container = NSPersistentContainer(name: "HabitModel", managedObjectModel: model)
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
            var failure: Error?
            container.loadPersistentStores { _, error in failure = error }
            if let failure { throw failure }
            return container
        }
        let first = try open()
        let habit = habit(in: first.viewContext)
        let id = habit.id
        let link = link(habit, in: first.viewContext)
        link.ekReminderID = "legacy-item"
        let completion = row(habit, daysAgo: 5, source: "manual", in: first.viewContext)
        try first.viewContext.save()
        let objectURI = habit.objectID.uriRepresentation()
        let completionID = completion.id
        for store in first.persistentStoreCoordinator.persistentStores {
            try first.persistentStoreCoordinator.remove(store)
        }
        let reopened = try open()
        let loaded = try XCTUnwrap(reopened.viewContext.fetch(Habit.fetchRequest()).first)
        XCTAssertEqual(loaded.id, id)
        XCTAssertEqual(loaded.objectID.uriRepresentation(), objectURI)
        let savedRow = try XCTUnwrap(reopened.viewContext.fetch(HabitCompletion.fetchRequest()).first)
        XCTAssertEqual(savedRow.id, completionID)
        XCTAssertTrue(savedRow.isComplete)
        XCTAssertEqual(savedRow.source, "manual")
        XCTAssertEqual(savedRow.totalRequired, 3)
        XCTAssertEqual(try reopened.viewContext.fetch(HabitReminderLink.fetchRequest()).first?.ekReminderID, "legacy-item")
        XCTAssertEqual(reopened.persistentStoreDescriptions.first?.url, url)
    }

    func testWidgetRejectsDeletedHabitWithoutDeletingCacheFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = WidgetHabitTodayPayload(updatedAt: now, habitID: "old", habitName: "Keep history",
            totalRequired: 2, completedRequired: 2, isComplete: true, days: [])
        WidgetSharedStore.writeToday(payload, directory: directory)
        WidgetSharedStore.writeHabitsIndex(WidgetHabitsIndexPayload(updatedAt: now,
            habits: [WidgetHabitStub(id: "old", name: "Keep history")]), directory: directory)
        XCTAssertNotNil(WidgetSharedStore.readToday(habitID: "old", directory: directory))
        WidgetSharedStore.writeHabitsIndex(WidgetHabitsIndexPayload(updatedAt: now, habits: []), directory: directory)
        XCTAssertNil(WidgetSharedStore.readToday(habitID: "old", directory: directory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(
            WidgetSharedStore.todayFileName(for: "old")).path))
        XCTAssertNil(WidgetSharedStore.readToday(habitID: "other", directory: directory))
    }

    func testWidgetWriterPublishesCorrectCountsAndEmptyIndexAfterDeletion() throws {
        let context = context()
        let habit = habit(in: context)
        let completion = row(habit, daysAgo: 0, in: context)
        completion.date = Calendar.current.startOfDay(for: Date())
        try context.save()
        let hid = HabitID.stableString(for: habit.objectID)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        WidgetDataWriter.writeSnapshot(in: context, directory: directory)
        let payload = try XCTUnwrap(WidgetSharedStore.readToday(habitID: hid, directory: directory))
        XCTAssertEqual(payload.totalRequired, 3)
        XCTAssertEqual(payload.completedRequired, 3)
        XCTAssertTrue(payload.isComplete)
        context.delete(habit)
        try context.save()
        WidgetDataWriter.writeSnapshot(in: context, directory: directory)
        XCTAssertEqual(WidgetSharedStore.readHabitsIndex(directory: directory)?.habits.count, 0)
        XCTAssertEqual(WidgetSharedStore.readSnapshot(directory: directory)?.totalHabits, 0)
        XCTAssertNil(WidgetSharedStore.readToday(habitID: hid, directory: directory))
    }
    func testMidnightHidesStaleTodaySummaryButRetainsHistoricalPayload() throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let payload = WidgetHabitTodayPayload(updatedAt: yesterday, habitID: "habit", habitName: "History",
            totalRequired: 1, completedRequired: 1, isComplete: true,
            days: [WidgetDay(dateKey: "2026-11-08", isComplete: true)])
        XCTAssertNil(WidgetSharedStore.currentSummary(payload, now: now))
        XCTAssertNotNil(WidgetSharedStore.currentSummary(payload, now: yesterday))
        XCTAssertEqual(payload.days.first?.isComplete, true)
    }

    func testOptionalLinksDoNotBlockTodayAndHabitsDoNotShareCompletions() throws {
        let context = context()
        let first = habit(in: context, name: "First")
        _ = link(first, in: context)
        _ = link(first, key: "optional", required: false, in: context)
        let second = habit(in: context, name: "Second")
        _ = link(second, key: "other", in: context)
        try HabitCompletionEngine.updateToday(in: context, reminders: [reminder()], now: now)
        let rows = try context.fetch(HabitCompletion.fetchRequest())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.habit, first)
        XCTAssertEqual(rows.first?.totalRequired, 1)
        XCTAssertEqual(rows.first?.isComplete, true)
    }

    func testLinkSaveIsIdempotentAndPreservesExistingLinksAndReminderMetadata() throws {
        let context = context()
        let first = habit(in: context, name: "First")
        let second = habit(in: context, name: "Second")
        let reminder = reminder()
        reminder.notes = "Do not replace"
        let originalURL = reminder.url
        try ReminderLinker.save([reminder], requiredKeys: ["linked"], habit: first, in: context)
        try ReminderLinker.save([reminder], requiredKeys: [], habit: first, in: context)
        try ReminderLinker.save([reminder], requiredKeys: ["linked"], habit: second, in: context)
        let links = try context.fetch(HabitReminderLink.fetchRequest())
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.habit, first)
        XCTAssertEqual(links.first?.isRequired, true)
        XCTAssertEqual(links.first?.reminderIdentifier, "linked")
        XCTAssertEqual(reminder.url, originalURL)
        XCTAssertEqual(reminder.notes, "Do not replace")
    }

    func testFailedLinkSaveDoesNotRollBackUnrelatedPendingEdits() throws {
        let context = context()
        let habit = habit(in: context)
        try context.save()
        habit.name = "Unsaved user edit"
        let invalidExistingLink = HabitReminderLink(context: context) // Required habit is absent.
        XCTAssertThrowsError(try ReminderLinker.save([reminder()], requiredKeys: ["linked"],
                                                   habit: habit, in: context))
        XCTAssertEqual(habit.name, "Unsaved user edit")
        XCTAssertTrue(context.insertedObjects.contains(invalidExistingLink))
        let links = try context.fetch(HabitReminderLink.fetchRequest())
        XCTAssertFalse(links.contains { $0.habit == habit })
    }

    func testInterruptedWidgetPublicationCannotDisplayRemovedHabitAggregate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        WidgetSharedStore.writeHabitsIndex(WidgetHabitsIndexPayload(updatedAt: now, habits: []), directory: directory)
        WidgetSharedStore.writeSnapshot(WidgetSnapshot(updatedAt: now,
            days: [WidgetDay(dateKey: "2026-11-09", isComplete: true)], totalHabits: 1, completeHabits: 1),
            directory: directory)
        XCTAssertNil(WidgetSharedStore.readSnapshot(directory: directory))
    }

}
