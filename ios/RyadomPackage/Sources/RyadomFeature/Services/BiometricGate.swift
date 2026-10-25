import Foundation
import LocalAuthentication
import Observation

public protocol BiometricAuthenticating: Sendable {
    /// Face ID / Touch ID, при недоступности — код-пароль устройства (системный резервный способ).
    func authenticate(reason: String) async -> Bool
}

public struct SystemBiometricAuthenticator: BiometricAuthenticating {
    public init() {}

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Блокировка раздела «Документы». Защищает интерфейс на устройстве; права доступа проверяет сервер.
@Observable
@MainActor
public final class DocumentsLock {
    public static let defaultsKey = "documentsProtection"

    public private(set) var isUnlocked = false
    public var isProtectionEnabled: Bool {
        didSet {
            defaults.set(isProtectionEnabled, forKey: Self.defaultsKey)
            if isProtectionEnabled { isUnlocked = false } else { isUnlocked = true }
        }
    }

    private let defaults: UserDefaults
    private let authenticator: any BiometricAuthenticating

    public init(defaults: UserDefaults = .standard, authenticator: any BiometricAuthenticating = SystemBiometricAuthenticator()) {
        self.defaults = defaults
        self.authenticator = authenticator
        let enabled = defaults.bool(forKey: Self.defaultsKey)
        self.isProtectionEnabled = enabled
        self.isUnlocked = !enabled
    }

    /// Нужно ли показывать содержимое: защита выключена или уже снята.
    public var isContentVisible: Bool { !isProtectionEnabled || isUnlocked }

    @discardableResult
    public func unlock() async -> Bool {
        guard isProtectionEnabled else { return true }
        let ok = await authenticator.authenticate(reason: "Откройте документы вашей семьи")
        if ok { isUnlocked = true }
        return ok
    }

    /// Вызывается, когда приложение уходит в фон.
    public func lock() {
        if isProtectionEnabled { isUnlocked = false }
    }
}
