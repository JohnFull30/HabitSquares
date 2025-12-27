//
//  HeatmapPalette.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/26/25.
//

import SwiftUI

/// One source of truth for how squares map to colors/intensity.
/// Key rule:
/// - If completed == 0, show EMPTY (neutral gray). No green tint until you make progress.
struct HeatmapPalette: Sendable {

    /// Truly empty / 0-progress square (neutral)
    var empty: Color = Color(uiColor: .systemGray5)

    /// Used when a day has a row but totals are unknown (neutral, not tinted)
    var startedNeutral: Color = Color(uiColor: .systemGray4)

    /// Opacity range for progress-based intensity (0%...100%)
    /// NOTE: only applied when ratio > 0 && ratio < 1
    var progressMinOpacity: Double = 0.35
    var progressMaxOpacity: Double = 1.0

    func color(base: Color, completed: Int?, total: Int?) -> Color {
        // No row at all (no completion record / no requirements that day)
        guard let completed, let total else { return empty }

        // Defensive / unknown totals -> neutral “started”
        if total <= 0 { return startedNeutral }

        let ratio = max(0.0, min(1.0, Double(completed) / Double(total)))

        // ✅ IMPORTANT: 0% progress should look empty/neutral, not tinted green
        if ratio <= 0.0 { return empty }

        // Full complete
        if ratio >= 1.0 { return base }

        // Progress intensity (continuous for now)
        let opacity = progressMinOpacity + (progressMaxOpacity - progressMinOpacity) * ratio
        return base.opacity(opacity)
    }

    /// Convenience when you only know "has row" vs "complete"
    /// - hasRow true but incomplete -> neutral started (not tinted)
    func color(base: Color, isComplete: Bool, hasRow: Bool) -> Color {
        if isComplete { return base }
        if hasRow { return startedNeutral }
        return empty
    }
}
