import Testing
import Foundation
import SwiftData
@testable import RyadomFeature

@Suite struct QuietHoursTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
    }

    private var quiet: NotificationSettings {
        var s = NotificationSettings()
        s.quietHoursEnabled = true
        return s
    }

    @Test func windowAcrossMidnight() {
        #expect(QuietHours.contains(minuteOfDay: 23 * 60, start: 22 * 60, end: 8 * 60))
        #expect(QuietHours.contains(minuteOfDay: 3 * 60, start: 22 * 60, end: 8 * 60))
        #expect(!QuietHours.contains(minuteOfDay: 8 * 60, start: 22 * 60, end: 8 * 60))
        #expect(!QuietHours.contains(minuteOfDay: 12 * 60, start: 22 * 60, end: 8 * 60))
    }

    @Test func emptyWindowIsNeverQuiet() {
        #expect(!QuietHours.contains(minuteOfDay: 600, start: 600, end: 600))
    }

    @Test func disabledKeepsFireDate() {
        let fire = date(10, 23)
        #expect(QuietHours.adjusted(fire, due: date(11, 9), settings: NotificationSettings(), calendar: calendar) == fire)
    }

    @Test func reminderInsideWindowMovesToMorning() {
        let shifted = QuietHours.adjusted(date(10, 23, 30), due: date(11, 9), settings: quiet, calendar: calendar)
        #expect(shifted == date(11, 8))
    }

    @Test func reminderEarlyMorningMovesToSameDayEnd() {
        let shifted = QuietHours.adjusted(date(11, 3), due: date(11, 9), settings: quiet, calendar: calendar)
        #expect(shifted == date(11, 8))
    }

    @Test func reminderDroppedWhenShiftWouldMissDeadline() {
        #expect(QuietHours.adjusted(date(10, 23), due: date(11, 6), settings: quiet, calendar: calendar) == nil)
    }

    @Test func reminderOutsideWindowIsUntouched() {
        let fire = date(10, 14)
        #expect(QuietHours.adjusted(fire, due: date(10, 15), settings: quiet, calendar: calendar) == fire)
    }
}

@MainActor @Suite struct AppSettingsTests {
    @Test func persistsBetweenLaunches() throws {
        let suite = "settings-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        #expect(first.notifications == NotificationSettings())
        first.notifications.taskReminders = false
        first.notifications.defaultReminderMinutes = 60

        let second = AppSettings(defaults: defaults)
        #expect(second.notifications.taskReminders == false)
        #expect(second.notifications.defaultReminderMinutes == 60)
    }
}

@MainActor @Suite struct ReminderSettingsTests {
    private let family = UUID()
    private let user = UUID()
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return c
    }

    private func reminders(_ settings: NotificationSettings, dueHour: Int) async throws -> [TaskReminder] {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
        let fake = FakeReminderScheduler()
        let service = TaskService(context: context, familyId: family, userId: user, calendar: cal,
                                  now: { now }, reminders: fake, settings: settings)
        var draft = TaskDraft(start: cal.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: dueHour))!)
        draft.title = "Дело"
        draft.assigneeId = user
        draft.reminderMinutes = 30
        _ = service.create(draft)
        return service.pendingReminders()
    }

    @Test func remindersOffProducesNone() async throws {
        var s = NotificationSettings()
        s.taskReminders = false
        #expect(try await reminders(s, dueHour: 15).isEmpty)
    }

    @Test func quietHoursMoveReminderToMorning() async throws {
        var s = NotificationSettings()
        s.quietHoursEnabled = true
        let list = try await reminders(s, dueHour: 8)  // 07:30 попадает в 22:00–08:00, но срок 08:00 — перенос на 08:00 допустим
        #expect(list.count == 1)
        #expect(list.first?.fireDate == calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 8)))
    }
}
