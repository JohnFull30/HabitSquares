//
//  WidgetRefresh.swift
//  Habit Tracker
//
//  Created by John Fuller on 1/14/26.
//


import Foundation
import CoreData
import WidgetKit

/// Single place to push the latest Core Data state into the widget cache + refresh WidgetKit.
enum WidgetRefresh {
    static func push(_ context: NSManagedObjectContext) {
        // Writes App Group JSON files the widget reads
        WidgetCacheWriter.writeTodayAndIndex(in: context)

        // Prompts the widget to re-render quickly
        WidgetCenter.shared.reloadAllTimelines()
    }
}
