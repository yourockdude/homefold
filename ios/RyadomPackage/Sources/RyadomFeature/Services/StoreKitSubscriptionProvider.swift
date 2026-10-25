import Foundation
import StoreKit

/// Подписки через StoreKit 2. Чтобы продукты появились при отладке без платного аккаунта, в схеме Xcode
/// (Run → Options → StoreKit Configuration) выберите `StoreKit/Products.storekit`.
@MainActor
final class StoreKitSubscriptionProvider: SubscriptionProviding {
    private var products: [String: Product] = [:]

    func loadPlans() async throws -> [PlusPlan] {
        let loaded = try await Product.products(for: PlusProduct.all)
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        return PlusProduct.all.compactMap { id in
            products[id].map {
                PlusPlan(id: $0.id, price: $0.price, currencyCode: $0.priceFormatStyle.currencyCode, displayPrice: $0.displayPrice)
            }
        }
    }

    func purchase(_ planId: String) async throws -> PurchaseResult {
        if products[planId] == nil { _ = try await loadPlans() }
        guard let product = products[planId] else { throw StoreKitError.unknown }
        switch try await product.purchase() {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return .success
            case .unverified:
                throw StoreKitError.unknown
            }
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: return .cancelled
        }
    }

    func restore() async throws { try await AppStore.sync() }

    func activeEntitlement() async -> EntitlementInfo? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PlusProduct.all.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  (transaction.expirationDate ?? .distantFuture) > .now else { continue }
            return EntitlementInfo(productId: transaction.productID, signedTransaction: result.jwsRepresentation,
                                   expiresAt: transaction.expirationDate)
        }
        return nil
    }

    func entitlementChanges() -> AsyncStream<EntitlementInfo?> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                for await update in Transaction.updates {
                    if case .verified(let transaction) = update { await transaction.finish() }
                    continuation.yield(await self.activeEntitlement())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
