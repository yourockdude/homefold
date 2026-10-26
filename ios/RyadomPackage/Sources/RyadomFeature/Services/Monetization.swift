import Foundation
import Security

/// Что доступно семье сейчас: пробный период, подписка или ничего (после пробного периода).
public enum AccessState: Equatable, Sendable {
    /// Пробный период идёт. `daysLeft` — сколько дней осталось, считая текущий (1…14).
    case trial(daysLeft: Int, endsAt: Date)
    case subscribed
    /// Пробный период закончился, подписки нет: приложение закрыто пейволом.
    case expired

    public var hasAccess: Bool { self != .expired }
}

/// Модель монетизации: 14 дней полного доступа, дальше — подписка HomeFold Plus. Бесплатного тарифа нет.
public enum Monetization {
    public static let trialDays = 14
    /// За сколько дней до конца пробного периода «Обзор» начинает напоминать о подписке.
    public static let reminderDays = 7

    public static func trialEnd(start: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: trialDays, to: start) ?? start.addingTimeInterval(TimeInterval(trialDays) * 86_400)
    }

    /// Состояние доступа. Пока дата старта неизвестна (семья только создана), пробный период считается начавшимся сейчас.
    public static func state(hasPlan: Bool, trialStart: Date?, now: Date = .now, calendar: Calendar = .current) -> AccessState {
        if hasPlan { return .subscribed }
        let end = trialEnd(start: trialStart ?? now, calendar: calendar)
        guard now < end else { return .expired }
        let left = Int((end.timeIntervalSince(now) / 86_400).rounded(.up))
        return .trial(daysLeft: min(max(left, 1), trialDays), endsAt: end)
    }
}

extension FamilyRecord {
    /// Тариф оплачен (подписка действует).
    public var hasPlan: Bool { plan == "plus" }

    public func accessState(now: Date = .now, calendar: Calendar = .current) -> AccessState {
        Monetization.state(hasPlan: hasPlan, trialStart: trialStartedAt, now: now, calendar: calendar)
    }
}

// MARK: Хранение даты начала пробного периода

/// Дата начала пробного периода живёт вне базы приложения, чтобы удаление и повторная установка не давали новый период.
public protocol TrialStoring: AnyObject, Sendable {
    /// Сохранённая дата начала; nil — пробный период ещё не начинался.
    func start() -> Date?
    /// Фиксирует начало, если его не было, и возвращает действующую дату.
    func begin(at date: Date) -> Date
}

/// В памяти: для тестов и отладочных запусков.
public final class InMemoryTrialStore: TrialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date?

    public init(start: Date? = nil) { stored = start }

    public func start() -> Date? { lock.withLock { stored } }

    public func begin(at date: Date) -> Date {
        lock.withLock {
            if let stored { return stored }
            stored = date
            return date
        }
    }
}

/// Keychain: на устройстве переживает удаление приложения. Если Keychain недоступен (например, симулятор без
/// нужных прав подписи, ошибка `errSecMissingEntitlement`), дата сохраняется в UserDefaults — тогда пробный период
/// продолжается, но переустановка его обнулит.
public final class KeychainTrialStore: TrialStoring, @unchecked Sendable {
    private let service: String
    private let account = "trial-start"
    private let defaults: UserDefaults
    private var fallbackKey: String { "\(service).trialStart" }

    public init(service: String = "app.ryadom.trial", defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func start() -> Date? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, let text = String(data: data, encoding: .utf8), let seconds = TimeInterval(text) {
            return Date(timeIntervalSince1970: seconds)
        }
        let stored = defaults.double(forKey: fallbackKey)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    public func begin(at date: Date) -> Date {
        if let existing = start() { return existing }
        var item = query
        item[kSecValueData as String] = Data(String(date.timeIntervalSince1970).utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(item as CFDictionary, nil) != errSecSuccess {
            defaults.set(date.timeIntervalSince1970, forKey: fallbackKey)
        }
        return date
    }

    /// Только для отладки и тестов.
    public func reset() {
        SecItemDelete(query as CFDictionary)
        defaults.removeObject(forKey: fallbackKey)
    }
}
