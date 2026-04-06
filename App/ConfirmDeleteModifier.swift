//
//  ConfirmDeleteModifier.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/6/26.
//


import SwiftUI

struct ConfirmDeleteModifier<Item>: ViewModifier {
    @Binding var item: Item?

    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: (Item) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(
                get: { item != nil },
                set: { newValue in
                    if !newValue {
                        item = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(confirmTitle, role: .destructive) {
                if let item {
                    onConfirm(item)
                    self.item = nil
                }
            }

            Button("Cancel", role: .cancel) {
                item = nil
            }
        } message: {
            Text(message)
        }
    }
}

extension View {
    func confirmDelete<Item>(
        item: Binding<Item?>,
        title: String = "Are you sure?",
        message: String,
        confirmTitle: String = "Delete",
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        modifier(
            ConfirmDeleteModifier(
                item: item,
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                onConfirm: onConfirm
            )
        )
    }
}