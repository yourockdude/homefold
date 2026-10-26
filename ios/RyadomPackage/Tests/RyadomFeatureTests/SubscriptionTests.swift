import Testing
import Foundation
import SwiftData
@testable import RyadomFeature

@MainActor
final class FakeSubscriptionProvider: SubscriptionProviding {
    var plans: [PlusPlan] = [
        PlusPlan(id: PlusProduct.yearly, price: 2490, currencyCode: "RUB", displayPrice: "2 490 ₽"),
        PlusPlan(id: PlusProduct.monthly, price: 299, currencyCode: "RUB", displayPrice: "299 ₽"),
    ]
    var purchaseResult: PurchaseResult = .success
    var purchaseError: Error?
    var restoreError: Error?
    var entitlement: EntitlementInfo?
    /// Подписка, которая появляется после успешной покупки или восстановления.
    let granted = EntitlementInfo(productId: PlusProduct.yearly, signedTransaction: "jws", expiresAt: nil)
    var restoreGrants = false

    struct Failure: Error {}

    func loadPlans() async throws -> [PlusPlan] { plans }
    func purchase(_ planId: String) async throws -> PurchaseResult {
        if let purchaseError { throw purchaseError }
        if purchaseResult == .success { entitlement = granted }
        return purchaseResult
    }
    func restore() async throws {
        if let restoreError { throw restoreError }
        if restoreGrants { entitlement = granted }
    }
    func activeEntitlement() async -> EntitlementInfo? { entitlement }
    func entitlementChanges() -> AsyncStream<EntitlementInfo?> { AsyncStream { $0.finish() } }
}

@MainActor @Suite struct SubscriptionStoreTests {
    let provider = FakeSubscriptionProvider()
    var store: SubscriptionStore { SubscriptionStore(provider: provider) }

    @Test func startLoadsPlansAndEntitlement() async {
        let store = store
        await store.start()
        #expect(store.plans.count == 2)
        #expect(store.yearly?.isYearly == true && store.monthly?.isYearly == false)
        #expect(store.hasCheckedEntitlement && !store.isPlus)
    }

    @Test func successfulPurchaseActivatesPlus() async throws {
        let store = store
        await store.start()
        let plan = try #require(store.yearly)
        #expect(await store.purchase(plan))
        #expect(store.isPlus && store.errorMessage == nil && store.phase == .idle)
    }

    @Test func cancelledPurchaseKeepsFree() async throws {
        provider.purchaseResult = .cancelled
        let store = store
        await store.start()
        #expect(await store.purchase(try #require(store.monthly)) == false)
        #expect(!store.isPlus && store.errorMessage == nil)
    }

    @Test func pendingPurchaseExplainsWaiting() async throws {
        provider.purchaseResult = .pending
        let store = store
        await store.start()
        #expect(await store.purchase(try #require(store.monthly)) == false)
        #expect(store.errorMessage?.contains("подтверждени") == true)
    }

    @Test func failedPurchaseShowsError() async throws {
        provider.purchaseError = FakeSubscriptionProvider.Failure()
        let store = store
        await store.start()
        #expect(await store.purchase(try #require(store.yearly)) == false)
        #expect(store.errorMessage != nil && !store.isPlus && store.phase == .idle)
    }

    @Test func restoreWithoutSubscriptionSaysSo() async {
        let store = store
        await store.start()
        #expect(await store.restore() == false)
        #expect(store.errorMessage?.contains("не найдено") == true)
    }

    @Test func restoreFindsSubscription() async {
        provider.restoreGrants = true
        let store = store
        await store.start()
        #expect(await store.restore())
        #expect(store.isPlus && store.errorMessage == nil)
    }

    @Test func savingsPercentIsComputedAgainstTwelveMonths() async {
        let store = store
        await store.start()
        #expect(store.savingsPercent == 31) // 299 × 12 = 3588; 2490 — на 30,6 % меньше
        #expect(PlusPricing.savingsPercent(monthly: 100, yearly: 1200) == nil)
        #expect(PlusPricing.savingsPercent(monthly: 0, yearly: 100) == nil)
    }
}

@MainActor @Suite struct PlanApplyingTests {
    let context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
    let granted = EntitlementInfo(productId: PlusProduct.yearly, signedTransaction: "jws.token", expiresAt: nil)

    private func outbox() -> [OutboxOperation] { (try? context.fetch(FetchDescriptor<OutboxOperation>())) ?? [] }

    @Test func adminActivatesPlusAndQueuesReceipt() throws {
        let service = FamilyService(context: context)
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        try service.applyPlus(granted, to: family, by: me.id)
        #expect(family.hasPlan && family.planIsLocal)
        let op = try #require(outbox().first { $0.entity == .subscription })
        #expect(String(data: op.payload, encoding: .utf8)?.contains("jws.token") == true)
    }

    @Test func memberCannotActivatePlus() throws {
        let service = FamilyService(context: context)
        let (family, admin) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        _ = admin
        let member = MemberRecord(id: UUID(), familyId: family.id, displayName: "Соня", role: "member", toneIndex: 1)
        context.insert(member)
        #expect(throws: FamilyError.notAdmin) { try service.applyPlus(granted, to: family, by: member.id) }
        #expect(!family.hasPlan)
    }


    @Test func expiredLocalSubscriptionDowngrades() throws {
        let service = FamilyService(context: context)
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        try service.applyPlus(granted, to: family, by: me.id)
        try service.applyPlus(nil, to: family, by: me.id)
        #expect(!family.hasPlan && !family.planIsLocal)
    }

    @Test func serverPlanIsNotDowngradedLocally() throws {
        let service = FamilyService(context: context)
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        family.plan = "plus" // пришёл с сервера
        try service.applyPlus(nil, to: family, by: me.id)
        #expect(family.hasPlan)
    }
}
