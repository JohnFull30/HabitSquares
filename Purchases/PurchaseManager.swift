import Foundation
import Combine
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    enum ProductID {
        static let founderLifetimePro = "PullerLabs.HabitSquares.founderLifetimePro"
        static let smallTip = "PullerLabs.HabitSquares.tip.small"
        static let mediumTip = "PullerLabs.HabitSquares.tip.medium"
        static let largeTip = "PullerLabs.HabitSquares.tip.large"
        static let extraGenerousTip = "PullerLabs.HabitSquares.tip.extraGenerous"
        static let tipUnit = "PullerLabs.HabitSquares.tip.unit"

        static let all: Set<String> = [
            founderLifetimePro,
            smallTip,
            mediumTip,
            largeTip,
            extraGenerousTip,
            tipUnit
        ]

        static let tips: Set<String> = [
            smallTip,
            mediumTip,
            largeTip,
            extraGenerousTip
        ]
    }

    static let freeHabitLimit = 3

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var activePurchaseProductID: String?
    @Published var errorMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    var isPro: Bool {
        purchasedProductIDs.contains(ProductID.founderLifetimePro)
    }

    var founderLifetimeProduct: Product? {
        products.first { $0.id == ProductID.founderLifetimePro }
    }

    var tipProducts: [Product] {
        products
            .filter { ProductID.tips.contains($0.id) }
            .sorted { lhs, rhs in
                sortOrder(for: lhs.id) < sortOrder(for: rhs.id)
            }
    }

    var tipUnitProduct: Product? {
        products.first { $0.id == ProductID.tipUnit }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func start() {
        guard transactionUpdatesTask == nil else { return }

        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                print("Transaction update received")
                await self.handle(transactionResult: result)
            }
        }

        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    func canCreateHabit(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freeHabitLimit
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            print("Loading StoreKit products: \(ProductID.all.sorted())")
            let loadedProducts = try await Product.products(for: ProductID.all)
            products = loadedProducts.sorted { lhs, rhs in
                sortOrder(for: lhs.id) < sortOrder(for: rhs.id)
            }
            print("Loaded StoreKit products: \(products.map(\.id))")
        } catch {
            errorMessage = "Unable to load purchases. Please try again later."
            print("Failed to load StoreKit products: \(error)")
        }
    }

    func purchase(_ product: Product, quantity: Int = 1) async {
        let safeQuantity = max(1, quantity)

        print("PURCHASE STARTED: \(product.id), quantity: \(safeQuantity)")
        errorMessage = nil
        activePurchaseProductID = product.id
        defer { activePurchaseProductID = nil }

        do {
            let result: Product.PurchaseResult
            if safeQuantity > 1 {
                result = try await product.purchase(options: [.quantity(safeQuantity)])
            } else {
                result = try await product.purchase()
            }

            switch result {
            case .success(let verification):
                print("PURCHASE RESULT SUCCESS: \(product.id), quantity: \(safeQuantity)")

                let transaction: Transaction
                do {
                    transaction = try checkVerified(verification)
                } catch {
                    print("VERIFICATION FAILED: \(product.id), error: \(error)")
                    throw error
                }

                await transaction.finish()
                print("TRANSACTION FINISHED: \(transaction.productID), transactionID: \(transaction.id)")
                await updatePurchasedProducts()

            case .userCancelled:
                print("PURCHASE CANCELLED: \(product.id)")
                break

            case .pending:
                print("PURCHASE RESULT PENDING: \(product.id)")
                errorMessage = "Purchase is pending approval."

            @unknown default:
                print("Unknown purchase result for product: \(product.id)")
                errorMessage = "Unable to complete purchase."
            }
        } catch {
            errorMessage = "Unable to complete purchase. Please try again."
            print("Failed to purchase \(product.id): \(error)")
        }
    }

    func restorePurchases() async {
        errorMessage = nil

        do {
            print("Restore purchases started")
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = "Unable to restore purchases. Please try again."
            print("Failed to restore purchases: \(error)")
        }
    }

    private func handle(transactionResult result: VerificationResult<Transaction>) async {
        do {
            let transaction: Transaction
            do {
                transaction = try checkVerified(result)
            } catch {
                print("VERIFICATION FAILED: transaction update, error: \(error)")
                throw error
            }

            await transaction.finish()
            print("TRANSACTION FINISHED: \(transaction.productID), transactionID: \(transaction.id)")
            await updatePurchasedProducts()
        } catch {
            print("Received unverified transaction: \(error)")
        }
    }

    private func updatePurchasedProducts() async {
        var purchasedIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                guard transaction.revocationDate == nil else { continue }

                if transaction.productID == ProductID.founderLifetimePro {
                    purchasedIDs.insert(transaction.productID)
                }
            } catch {
                print("Skipping unverified entitlement: \(error)")
            }
        }

        purchasedProductIDs = purchasedIDs
        print("ENTITLEMENTS REFRESHED: \(purchasedProductIDs.sorted())")
        print("IS PRO: \(isPro)")
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private func sortOrder(for productID: String) -> Int {
        switch productID {
        case ProductID.founderLifetimePro:
            return 0
        case ProductID.smallTip:
            return 1
        case ProductID.mediumTip:
            return 2
        case ProductID.largeTip:
            return 3
        case ProductID.extraGenerousTip:
            return 4
        case ProductID.tipUnit:
            return 5
        default:
            return 99
        }
    }
}

private enum StoreError: Error {
    case failedVerification
}
