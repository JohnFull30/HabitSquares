//
//  HabitWidgetConfigurationIntent.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/25/25.
//


import AppIntents

struct HabitWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Habit"
    static var description = IntentDescription("Choose which habit this widget displays.")

    @Parameter(title: "Habit")
    var habit: WidgetHabitEntity?
}