import Foundation
import UserNotifications

/// Локальное напоминание о деле.
public struct TaskReminder: Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
}

public protocol ReminderScheduling: Sendable {
    /// Запрашивает разрешение, если оно ещё не запрашивалось. Отказ не блокирует приложение.
    func requestAuthorizationIfNeeded() async -> Bool
    /// Заменяет все запланированные напоминания переданным набором: лишние снимаются, дублей нет.
    func replaceAll(with reminders: [TaskReminder]) async
}

/// Реализация на UserNotifications. Идентификатор запроса — идентификатор выполнения, поэтому повторное
/// планирование перезаписывает прежнее уведомление, а не добавляет второе.
public struct SystemReminderScheduler: ReminderScheduling {
    static let prefix = "task."
    /// iOS хранит не более 64 ожидающих уведомлений.
    public static let limit = 60

    public init() {}

    public func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    public func replaceAll(with reminders: [TaskReminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for reminder in reminders.prefix(Self.limit) {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let parts = Calendar.current.dateComponents(in: .current, from: reminder.fireDate)
            var trigger = DateComponents()
            trigger.year = parts.year; trigger.month = parts.month; trigger.day = parts.day
            trigger.hour = parts.hour; trigger.minute = parts.minute; trigger.second = parts.second
            let request = UNNotificationRequest(
                identifier: Self.prefix + reminder.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false))
            try? await center.add(request)
        }
    }
}

/// Пустая реализация для тестов и режима без разрешений.
public struct NoopReminderScheduler: ReminderScheduling {
    public init() {}
    public func requestAuthorizationIfNeeded() async -> Bool { false }
    public func replaceAll(with reminders: [TaskReminder]) async {}
}
