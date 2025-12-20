import SwiftUI

struct HSCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10),
                radius: colorScheme == .dark ? 8 : 12,
                x: 0,
                y: 6
            )
    }
}

extension View {
    func hsCard() -> some View { modifier(HSCardStyle()) }
}
