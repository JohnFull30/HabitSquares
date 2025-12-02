import Foundation
import WidgetKit   // fine for both app + widget in iOS 17+

/// JSON model shared by app + widget.
/// Keys are "yyyy-MM-dd" strings in UTC.
struct HeatmapCache: Codable {
    let countsByDay: [String: Int]
}

enum CacheWriter {
    // MARK: - App Group configuration

    // NOTE: This must match the App Group ID in Signing & Capabilities
    private static let appGroupID = "group.john"

    private static let cacheFilename = "heatmapCache.json"

    private static var cacheURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(cacheFilename, isDirectory: false)
    }

    enum CacheError: Error {
        case missingContainer
    }

    // MARK: - Key helpers (Date <-> String)

    /// Convert a Date to the "yyyy-MM-dd" key both sides agree on.
    static func key(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Parse a "yyyy-MM-dd" key back into a Date.
    static func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    // MARK: - Read / write

    /// Read the cached heatmap from the shared App Group container.
    static func readSync() throws -> HeatmapCache? {
        guard let url = cacheURL else { throw CacheError.missingContainer }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(HeatmapCache.self, from: data)
    }

    /// Write the cached heatmap to the shared App Group container.
    static func writeSync(_ cache: HeatmapCache) throws {
        guard let url = cacheURL else { throw CacheError.missingContainer }

        let encoder = JSONEncoder()
        let data = try encoder.encode(cache)

        // Atomic write so the widget never sees a half-written file.
        try data.write(to: url, options: [.atomic])
    }
}
