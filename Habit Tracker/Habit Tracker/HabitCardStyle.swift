//
//  HabitCardStyle.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/20/25.
//


import SwiftUI

struct HabitCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12),
                radius: 18,
                x: 0,
                y: 10
            )
    }
}

extension View {
    func habitCardStyle() -> some View { modifier(HabitCardStyle()) }
}