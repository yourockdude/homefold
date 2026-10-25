import Foundation
import Observation

/// Идентификаторы подписок. Совпадают с `APPLE_PRODUCT_IDS` бэкенда.
public enum PlusProduct {
    public static let monthly = "app.ryadom.plus.monthly"
    public static let yearly = "app.ryadom.plus.yearly"
    public static let all = [yearly, monthly]
}

/// Тариф HomeFold Plus, как его видит пейвол.
public struct PlusPlan: Identifiable, Equatable, Sendable {
    public let id: String
    public let price: Decimal
    public let currencyCode: String
    /// Цена, отформатированная магазином.
    public let displayPrice: String

    public var isYearly: Bool { id == PlusProduct.yearly }
    public var title: String { isYearly ? "Год" : "Месяц" }

    public init(id: String, price: Decimal, currencyCode: String, displayPrice: String) {
        self.id = id
        self.price = price
        self.currencyCode = currencyCode
        self.displayPrice = displayPrice
    }
}

public enum PlusPricing {
    /// Во сколько процентов годовой тариф дешевле двенадцати месяцев; nil — выгоды нет.
    public static func savingsPercent(monthly: Decimal, yearly: Decimal) -> Int? {
        guard monthly > 0, yearly > 0 else { return nil }
        let full = monthly * 12
        let saved = (full - yearly) / full * 100
        let rounded = Int(NSDecimalNumber(decimal: saved).doubleValue.rounded())
        return rounded > 0 ? rounded : nil
    }

    /// Цена месяца при годовой подписке, отформатированная в валюте тарифа.
    public static func monthlyEquivalent(of yearly: PlusPlan) -> String {
        let value = yearly.price / 12
        return value.formatted(.currency(code: yearly.currencyCode).precision(.fractionLength(0)).locale(Locale(identifier: "ru_RU")))
    }
}

/// Действующая подписка Plus.
public struct EntitlementInfo: Equatable, Sendable {
    public let productId: String
    /// JWS транзакции — уходит на сервер (`POST /billing/verify`), который и решает, какой у семьи тариф.
    public let signedTransaction: String
    public let expiresAt: Date?

    public init(productId: String, signedTransaction: String, expiresAt: Date?) {
        self.productId = productId
        self.signedTransaction = signedTransaction
        self.expiresAt = expiresAt
    }
}

public enum PurchaseResult: Equatable, Sendable {
    case success
    case cancelled
    /// Ждёт одобрения (например, «Попросить купить» в семейном доступе).
    case pending
}

/// Источник подписок: StoreKit 2 или симулятор в отладочных сборках.
@MainActor
public protocol SubscriptionProviding {
    func loadPlans() async throws -> [PlusPlan]
    func purchase(_ planId: String) async throws -> PurchaseResult
    /// Синхронизация покупок с App Store («Восстановить»).
    func restore() async throws
    func activeEntitlement() async -> EntitlementInfo?
    /// Изменения подписки вне приложения: продление, отмена, возврат.
    func entitlementChanges() -> AsyncStream<EntitlementInfo?>
}

/// Состояние подписки и покупки. Сам тариф семьи выставляется отдельно (`FamilyService.applyPlus`).
@Observable
@MainActor
public final class SubscriptionStore {
    public enum Phase: Equatable { case idle, loadingPlans, purchasing, restoring }

    public private(set) var plans: [PlusPlan] = []
    public private(set) var entitlement: EntitlementInfo?
    public private(set) var phase: Phase = .idle
    /// Тарифы не удалось загрузить (нет сети, магазин недоступен).
    public private(set) var plansFailed = false
    /// Статус подписки уже получен от магазина; до этого понижать тариф семьи нельзя.
    public private(set) var hasCheckedEntitlement = false
    public var errorMessage: String?

    public var isPlus: Bool { entitlement != nil }
    public var yearly: PlusPlan? { plans.first { $0.isYearly } }
    public var monthly: PlusPlan? { plans.first { !$0.isYearly } }
    public var savingsPercent: Int? {
        guard let yearly, let monthly else { return nil }
        return PlusPricing.savingsPercent(monthly: monthly.price, yearly: yearly.price)
    }

    private let provider: any SubscriptionProviding

    public init(provider: any SubscriptionProviding) { self.provider = provider }

    /// Загружает тарифы и текущую подписку.
    public func start() async {
        await refreshEntitlement()
        await loadPlans()
    }

    public func loadPlans() async {
        phase = .loadingPlans
        defer { phase = .idle }
        do {
            plans = try await provider.loadPlans()
            plansFailed = plans.isEmpty
        } catch {
            plansFailed = true
        }
    }

    public func refreshEntitlement() async {
        entitlement = await provider.activeEntitlement()
        hasCheckedEntitlement = true
    }

    /// Слушает изменения подписки, пока жива задача.
    public func observeChanges() async {
        for await change in provider.entitlementChanges() {
            entitlement = change
            hasCheckedEntitlement = true
        }
    }

    /// Покупка выбранного тарифа. true — подписка действует.
    @discardableResult
    public func purchase(_ plan: PlusPlan) async -> Bool {
        phase = .purchasing
        errorMessage = nil
        defer { phase = .idle }
        do {
            switch try await provider.purchase(plan.id) {
            case .success:
                await refreshEntitlement()
                return isPlus
            case .cancelled:
                return false
            case .pending:
                errorMessage = "Покупка ждёт подтверждения. Plus включится, когда её одобрят."
                return false
            }
        } catch {
            errorMessage = "Не удалось оформить подписку. Проверьте интернет и попробуйте ещё раз."
            return false
        }
    }

    /// «Восстановить покупки». true — найдена действующая подписка.
    @discardableResult
    public func restore() async -> Bool {
        phase = .restoring
        errorMessage = nil
        defer { phase = .idle }
        do {
            try await provider.restore()
            await refreshEntitlement()
            if !isPlus { errorMessage = "Действующей подписки HomeFold Plus не найдено." }
            return isPlus
        } catch {
            errorMessage = "Не удалось связаться с App Store. Попробуйте позже."
            return false
        }
    }
}

#if DEBUG
/// Симулятор магазина для UI-тестов и отладки без StoreKit. Поведение — аргументами запуска:
/// `-RYStoreCancel` (пользователь отменил), `-RYStoreFail` (ошибка покупки), `-RYStoreNoPlans` (тарифы не загрузились).
@MainActor
final class SimulatedSubscriptionProvider: SubscriptionProviding {
    private var entitlement: EntitlementInfo?
    private var continuation: AsyncStream<EntitlementInfo?>.Continuation?
    private let args = ProcessInfo.processInfo.arguments

    struct SimulatedError: Error {}

    func loadPlans() async throws -> [PlusPlan] {
        if args.contains("-RYStoreNoPlans") { throw SimulatedError() }
        return [
            PlusPlan(id: PlusProduct.yearly, price: 2490, currencyCode: "RUB", displayPrice: "2 490 ₽"),
            PlusPlan(id: PlusProduct.monthly, price: 299, currencyCode: "RUB", displayPrice: "299 ₽"),
        ]
    }

    func purchase(_ planId: String) async throws -> PurchaseResult {
        try? await Task.sleep(for: .milliseconds(500))
        if args.contains("-RYStoreFail") { throw SimulatedError() }
        if args.contains("-RYStoreCancel") { return .cancelled }
        let info = EntitlementInfo(productId: planId, signedTransaction: "simulated.\(planId).jws",
                                   expiresAt: .now.addingTimeInterval(planId == PlusProduct.yearly ? 365 * 86_400 : 30 * 86_400))
        entitlement = info
        continuation?.yield(info)
        return .success
    }

    func restore() async throws { try? await Task.sleep(for: .milliseconds(300)) }

    func activeEntitlement() async -> EntitlementInfo? { entitlement }

    func entitlementChanges() -> AsyncStream<EntitlementInfo?> {
        AsyncStream { self.continuation = $0 }
    }
}
#endif
