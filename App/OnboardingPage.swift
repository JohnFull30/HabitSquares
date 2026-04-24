//
//  OnboardingPage.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/24/26.
//


import Foundation

struct OnboardingPage: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let body: String
    let systemImage: String

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Build habits one square at a time",
            body: "HabitSquares turns your daily habits into a simple heatmap so you can see consistency at a glance.",
            systemImage: "square.grid.3x3.fill"
        ),
        OnboardingPage(
            title: "Green means fully done",
            body: "Each habit can link to one or more Apple Reminders. A day turns green only when all required linked reminders are completed for that day.",
            systemImage: "checkmark.circle.fill"
        ),
        OnboardingPage(
            title: "Use Apple Reminders when you're ready",
            body: "HabitSquares can link your reminders to each habit so your daily squares update automatically. You stay in control, and you can connect reminders when setting up a habit.",
            systemImage: "list.bullet.clipboard.fill"
        )
    ]
}