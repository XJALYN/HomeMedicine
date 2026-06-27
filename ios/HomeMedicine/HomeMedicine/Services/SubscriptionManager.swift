import Foundation
import StoreKit
import Combine

@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var tier: SubscriptionTier = .free
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published var purchaseErrorMessage: String?

    private var transactionListener: Task<Void, Never>?
    private let quotaStore: UsageQuotaStore

    init(quotaStore: UsageQuotaStore) {
        self.quotaStore = quotaStore
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: SubscriptionProductID.all)
                .sorted { $0.price < $1.price }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        if products.isEmpty {
            await loadProducts()
        }

        var resolvedTier: SubscriptionTier = .free

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            resolvedTier = Self.maxTier(resolvedTier, for: transaction.productID)
        }

        for productID in SubscriptionProductID.subscriptions {
            guard let product = product(for: productID),
                  let subscription = product.subscription,
                  let statuses = try? await subscription.status else { continue }
            for status in statuses {
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    resolvedTier = Self.maxTier(resolvedTier, for: productID)
                default:
                    break
                }
            }
        }

        tier = resolvedTier
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseErrorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await deliver(productID: transaction.productID)
                applyTier(for: transaction.productID)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        purchaseErrorMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    private func deliver(productID: String) async {
        if let credits = SubscriptionLimits.aiCreditsAmount(for: productID) {
            quotaStore.addPurchasedCredits(credits)
        }
    }

    private func applyTier(for productID: String) {
        tier = Self.maxTier(tier, for: productID)
    }

    private static func maxTier(_ current: SubscriptionTier, for productID: String) -> SubscriptionTier {
        guard let productTier = SubscriptionLimits.tier(for: productID),
              productTier.rank > current.rank else {
            return current
        }
        return productTier
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                do {
                    let transaction = try Self.checkVerified(result)
                    await self.deliver(productID: transaction.productID)
                    await MainActor.run {
                        self.applyTier(for: transaction.productID)
                    }
                    await transaction.finish()
                    await self.refreshEntitlements()
                } catch {
                    await MainActor.run {
                        self.purchaseErrorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        try Self.checkVerified(result)
    }

    nonisolated private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
