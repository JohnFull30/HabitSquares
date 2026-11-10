import StoreKit
import SwiftUI

struct ProUpgradeView: View {
    enum Reason {
        case habitLimit
        case settings
    }

    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    let reason: Reason

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Founder Lifetime Pro")
                            .font(.title2.weight(.bold))

                        Text(headerMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Included") {
                    Label("Create unlimited habits", systemImage: "square.grid.3x3.fill")
                    Label("Keep all current habit and reminder features", systemImage: "checkmark.seal.fill")
                    Label("One-time lifetime unlock", systemImage: "infinity")
                }

                Section {
                    if purchaseManager.isPro {
                        Label("Founder Lifetime Pro is active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if let product = purchaseManager.founderLifetimeProduct {
                        Button {
                            Task {
                                await purchaseManager.purchase(product)
                            }
                        } label: {
                            HStack {
                                Text("Unlock Founder Lifetime Pro")
                                Spacer()
                                if purchaseManager.activePurchaseProductID == product.id {
                                    ProgressView()
                                } else {
                                    Text(product.displayPrice)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(purchaseManager.activePurchaseProductID != nil)
                    } else {
                        Button {
                            Task {
                                await purchaseManager.loadProducts()
                            }
                        } label: {
                            HStack {
                                Text(purchaseManager.isLoading ? "Loading purchases..." : "Load purchase options")
                                Spacer()
                                if purchaseManager.isLoading {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(purchaseManager.isLoading)
                    }

                    Button("Restore Purchases") {
                        Task {
                            await purchaseManager.restorePurchases()
                        }
                    }
                }

                if let errorMessage = purchaseManager.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if purchaseManager.products.isEmpty {
                    await purchaseManager.loadProducts()
                }
            }
        }
    }

    private var headerMessage: String {
        switch reason {
        case .habitLimit:
            return "Free users can create up to \(PurchaseManager.freeHabitLimit) habits. Upgrade once to create as many habit squares as you want."
        case .settings:
            return "Support HabitSquares early and unlock unlimited habit creation forever."
        }
    }
}

struct TipDeveloperView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    let onCustomTip: () -> Void

    var body: some View {
        Section("Tip the Developer") {
            if purchaseManager.tipProducts.isEmpty {
                Button {
                    Task {
                        await purchaseManager.loadProducts()
                    }
                } label: {
                    HStack {
                        Text(purchaseManager.isLoading ? "Loading tips..." : "Load tip options")
                        Spacer()
                        if purchaseManager.isLoading {
                            ProgressView()
                        }
                    }
                }
                .disabled(purchaseManager.isLoading)
            } else {
                ForEach(purchaseManager.tipProducts, id: \.id) { product in
                    Button {
                        Task {
                            await purchaseManager.purchase(product)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayName)
                                Text(product.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if purchaseManager.activePurchaseProductID == product.id {
                                ProgressView()
                            } else {
                                Text(product.displayPrice)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(purchaseManager.activePurchaseProductID != nil)
                }

                if purchaseManager.tipUnitProduct != nil {
                    Button {
                        onCustomTip()
                    } label: {
                        Label("Custom Tip", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
    }
}

struct CustomTipView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var quantity = 5

    private let quantityRange = 1...50

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Custom Tip")
                            .font(.title2.weight(.bold))

                        Text("Choose how many tip units to send.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Amount") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Tip units")
                            Spacer()
                            Text("\(quantity)")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(quantity) },
                                set: { quantity = Int($0.rounded()) }
                            ),
                            in: Double(quantityRange.lowerBound)...Double(quantityRange.upperBound),
                            step: 1
                        )

                        Stepper("Quantity: \(quantity)", value: $quantity, in: quantityRange)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if let product = purchaseManager.tipUnitProduct {
                        Button {
                            Task {
                                await purchaseManager.purchase(product, quantity: quantity)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Send Custom Tip")
                                    Text("\(quantity) x \(product.displayPrice)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if purchaseManager.activePurchaseProductID == product.id {
                                    ProgressView()
                                } else {
                                    Text(estimatedTotal(for: product))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(purchaseManager.activePurchaseProductID != nil)
                    } else {
                        Button {
                            Task {
                                await purchaseManager.loadProducts()
                            }
                        } label: {
                            HStack {
                                Text(purchaseManager.isLoading ? "Loading tip options..." : "Load tip options")
                                Spacer()
                                if purchaseManager.isLoading {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(purchaseManager.isLoading)
                    }
                }

                if let errorMessage = purchaseManager.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Custom Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                if purchaseManager.products.isEmpty {
                    await purchaseManager.loadProducts()
                }
            }
        }
    }

    private func estimatedTotal(for product: Product) -> String {
        (product.price * Decimal(quantity)).formatted(product.priceFormatStyle)
    }
}
