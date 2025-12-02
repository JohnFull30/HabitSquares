//
//  HabitHeatmapView.swift
//  Habit Tracker
//
//  Created by John Fuller on 11/28/25.
//

import Foundation
import SwiftUI

/// Displays a single habit as a GitHub-style heatmap row.
struct HabitHeatmapView: View {
    let habit: HabitModel   // like props in React

    // 7 columns = 1 week wide, days will wrap downward
    private let columns = Array(repeating: GridItem(.fixed(20), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(habit.name)
                .font(.title2.bold())

            Text("Last \(habit.days.count) days")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(habit.days) { day in
                    daySquare(for: day)
                }
            }
        }
        .padding()
    }

    // MARK: - Square View

    @ViewBuilder
    private func daySquare(for day: HabitDay) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(squareColor(for: day))
            .frame(width: 20, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
            )
            .accessibilityLabel(
                Text("\(formattedDate(day.date)): \(day.isComplete ? "Complete" : "Incomplete")")
            )
            .help(formattedDate(day.date))
    }

    private func squareColor(for day: HabitDay) -> Color {
        day.isComplete ? Color.green : Color.gray.opacity(0.2)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    HabitHeatmapView(habit: HabitDemoData.makeSampleHabit())
}
