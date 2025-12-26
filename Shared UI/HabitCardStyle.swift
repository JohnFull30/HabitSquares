import SwiftUI

struct HabitCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.systemBackground)) // <-- was .thinMaterial
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.10),
                radius: 16,
                x: 0,
                y: 8
            )
    }
}

extension View {
    func habitCardStyle() -> some View { modifier(HabitCardStyle()) }
}
