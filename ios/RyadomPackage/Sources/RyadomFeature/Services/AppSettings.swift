import Foundation
import Observation

/// Настройки уведомлений на этом устройстве.
public struct NotificationSettings: Equatable, Sendable, Codable {
    public var taskReminders = true
    /// За сколько минут до срока напоминать о новых делах.
    public var defaultReminderMinutes = 30
    public var shoppingPush = true
    public var quietHoursEnabled = false
    /// Границы тихих часов — минуты от полуночи.
    public var quietStartMinutes = 22 * 60
    public var quietEndMinutes = 8 * 60

    public init() {}
}

/// Тихие часы: напоминания, попавшие в окно, переносятся на его конец.
public enum QuietHours {
    public static func contains(minuteOfDay: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end { return minuteOfDay >= start && minuteOfDay < end }
        return minuteOfDay >= start || minuteOfDay < end
    }

    /// Время показа с учётом тихих часов; nil — если после переноса напоминание опоздало бы к сроку.
    public static func adjusted(_ fire: Date, due: Date, settings: NotificationSettings, calendar: Calendar) -> Date? {
        guard settings.quietHoursEnabled else { return fire }
        let parts = calendar.dateComponents([.hour, .minute], from: fire)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard contains(minuteOfDay: minute, start: settings.quietStartMinutes, end: settings.quietEndMinutes) else { return fire }
        let endParts = DateComponents(hour: settings.quietEndMinutes / 60, minute: settings.quietEndMinutes % 60)
        guard let shifted = calendar.nextDate(after: fire, matching: endParts, matchingPolicy: .nextTime) else { return nil }
        return shifted <= due ? shifted : nil
    }
}

/// Хранилище настроек приложения (UserDefaults).
@Observable
@MainActor
public final class AppSettings {
    public static let defaultsKey = "notificationSettings"

    public var notifications: NotificationSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            notifications = stored
        } else {
            notifications = NotificationSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
