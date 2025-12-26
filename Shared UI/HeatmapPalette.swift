//
//  HeatmapPalette.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/26/25.
//


import SwiftUI

/// One source of truth for how squares map to colors/intensity.
struct HeatmapPalette: Sendable {
    var empty: Color = Color(.systemGray4)

    /// Opacity for incomplete-but-has-a-row (when total is unknown / or just "started")
    var startedOpacity: Double = 0.25

    /// Opacity range for progress-based intensity (0%...100%)
    var progressMinOpacity: Double = 0.25
    var progressMaxOpacity: Double = 1.0

    func color(base: Color, completed: Int?, total: Int?) -> Color {
        // No row at all
        guard let completed, let total else { return empty }

        // Defensive
        if total <= 0 { return base.opacity(startedOpacity) }

        let ratio = max(0.0, min(1.0, Double(completed) / Double(total)))

        // Full complete
        if ratio >= 1.0 { return base }

        // Progress intensity (you can make this more "GitHub-ish" later with discrete steps)
        let opacity = progressMinOpacity + (progressMaxOpacity - progressMinOpacity) * ratio
        return base.opacity(opacity)
    }

    /// Convenience when you only know "has row" vs "complete"
    func color(base: Color, isComplete: Bool, hasRow: Bool) -> Color {
        if isComplete { return base }
        if hasRow { return base.opacity(startedOpacity) }
        return empty
    }
}
