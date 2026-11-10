import CoreData

// Keep the existing entry point, with one implementation for all widget payloads.
enum WidgetCacheWriter {
    static func writeTodayAndIndex(in context: NSManagedObjectContext, dayCount: Int = 60) {
        WidgetDataWriter.writeSnapshot(dayCount: dayCount, in: context)
    }
}
