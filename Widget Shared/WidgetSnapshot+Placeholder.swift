import Foundation

extension WidgetSnapshot {
    static var placeholder: WidgetSnapshot {
        // IMPORTANT:
        // Type `WidgetSnapshot(` below and let Xcode autocomplete the required parameters.
        // Fill them with “empty” values (Date(), 0, "", []).
        WidgetSnapshot(
            updatedAt: Date(),
            completeHabits: 0,
            days: []
        )
    }
}
