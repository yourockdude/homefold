import Testing
import Foundation
import SwiftData
@testable import RyadomFeature

actor FakeReminderScheduler: ReminderScheduling {
    private(set) var last: [TaskReminder] = []
    private(set) var authorizationRequests = 0
    func requestAuthorizationIfNeeded() async -> Bool { authorizationRequests += 1; return false }
    func replaceAll(with reminders: [TaskReminder]) async { last = reminders }
}

@MainActor
struct TaskServiceTests {
    let context: ModelContext
    let service: TaskService
    let fake = FakeReminderScheduler()
    let calendar: Calendar
    let family = UUID()
    let user = UUID()
    let other = UUID()
    /// Четверг, 22 октября 2026, 12:00 (Москва).
    let today: Date

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
        cal.locale = Locale(identifier: "ru_RU")
        cal.firstWeekday = 2
        calendar = cal
        today = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let fixed = today
        context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
        service = TaskService(context: context, familyId: family, userId: user, calendar: cal,
                              now: { fixed }, reminders: fake)
    }

    private func at(_ day: Int, _ hour: Int = 18, _ minute: Int = 30, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func draft(_ title: String = "Полить растения", on date: Date? = nil, repeat r: Recurrence = .none) -> TaskDraft {
        var d = TaskDraft(start: date ?? at(22))
        d.title = title
        d.assigneeId = user
        d.recurrence = r
        return d
    }

    private func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
    private func ops() -> [OutboxOperation] { all(OutboxOperation.self) }

    // MARK: Создание

    @Test("Без названия дело не создаётся")
    func validation() {
        #expect(service.create(draft("   ")) == nil)
        #expect(all(TaskOccurrenceRecord.self).isEmpty)
    }

    @Test("Разовое дело: серия и одно выполнение, операции в очереди")
    func createSingle() throws {
        let occ = try #require(service.create(draft()))
        #expect(all(TaskSeriesRecord.self).count == 1)
        #expect(all(TaskOccurrenceRecord.self).count == 1)
        #expect(occ.syncStatus == .pending)
        #expect(ops().filter { $0.entity == .taskSeries }.count == 1)
        #expect(ops().filter { $0.entity == .taskOccurrence }.count == 1)
    }

    @Test("Еженедельное дело материализуется на 60 дней")
    func weeklyHorizon() throws {
        _ = try #require(service.create(draft(repeat: .weekly)))
        #expect(all(TaskOccurrenceRecord.self).count == 9)
    }

    @Test("Повторная достройка горизонта не создаёт дублей")
    func extendIsIdempotent() throws {
        _ = try #require(service.create(draft(repeat: .daily)))
        let before = all(TaskOccurrenceRecord.self).count
        service.extendHorizon()
        service.extendHorizon()
        #expect(all(TaskOccurrenceRecord.self).count == before)
        #expect(Set(all(TaskOccurrenceRecord.self).map(\.id)).count == before)
    }

    @Test("Ежемесячное 31-е число: февраль получает последнее число месяца")
    func monthlyClamp() {
        let start = at(31, month: 1, year: 2027)
        let dates = RecurrenceEngine.dates(start: start, recurrence: .monthly,
                                           until: at(1, month: 5, year: 2027), calendar: calendar)
        let days = dates.map { calendar.component(.day, from: $0) }
        #expect(days == [31, 28, 31, 30])
    }

    @Test("Удалённое выполнение не воскресает при достройке горизонта")
    func deletedStaysDeleted() throws {
        let first = try #require(service.create(draft(repeat: .daily)))
        let second = try #require(all(TaskOccurrenceRecord.self).sorted { $0.dueAt < $1.dueAt }.dropFirst().first)
        service.delete(second)
        service.extendHorizon()
        let alive = all(TaskOccurrenceRecord.self).filter { $0.deletedAt == nil }
        #expect(!alive.contains { $0.id == second.id })
        #expect(alive.contains { $0.id == first.id })
    }

    // MARK: Завершение

    @Test("Завершение одного выполнения не завершает серию")
    func completeOne() throws {
        let first = try #require(service.create(draft(repeat: .weekly)))
        service.complete(first)
        #expect(first.isCompleted)
        #expect(first.completedById == user)
        #expect(all(TaskOccurrenceRecord.self).filter(\.isCompleted).count == 1)
        service.reopen(first)
        #expect(!first.isCompleted)
        #expect(first.completedById == nil)
    }

    // MARK: Правка

    @Test("Правка выполнения меняет только его")
    func editOccurrenceOnly() throws {
        _ = try #require(service.create(draft(repeat: .weekly)))
        let sorted = all(TaskOccurrenceRecord.self).sorted { $0.dueAt < $1.dueAt }
        var d = TaskDraft(occurrence: sorted[1], recurrence: .weekly)
        d.title = "Полить цветы"
        #expect(service.update(sorted[1], with: d))
        #expect(sorted[1].title == "Полить цветы")
        #expect(sorted[1].isDetached)
        #expect(sorted[0].title == "Полить растения")
        #expect(sorted[2].title == "Полить растения")
    }

    @Test("Правка серии не трогает выполненные и отдельно изменённые выполнения")
    func editSeriesSkipsDetachedAndDone() throws {
        _ = try #require(service.create(draft(repeat: .weekly)))
        let s = all(TaskOccurrenceRecord.self).sorted { $0.dueAt < $1.dueAt }
        service.complete(s[0])
        var single = TaskDraft(occurrence: s[2], recurrence: .weekly)
        single.title = "Особое"
        _ = service.update(s[2], with: single)

        var seriesDraft = TaskDraft(occurrence: s[1], recurrence: .weekly)
        seriesDraft.title = "Новое название"
        #expect(service.updateSeries(from: s[1], with: seriesDraft))

        #expect(s[0].title == "Полить растения")
        #expect(s[1].title == "Новое название")
        #expect(s[2].title == "Особое")
        #expect(s[3].title == "Новое название")
    }

    @Test("Перенос меняет срок и не отмечает дело выполненным")
    func reschedule() throws {
        let occ = try #require(service.create(draft(on: at(21, 21, 0))))
        #expect(service.isOverdue(occ))
        service.reschedule(occ, to: at(22, 21, 0), hasTime: true)
        #expect(!occ.isCompleted)
        #expect(!service.isOverdue(occ))
        #expect(occ.isDetached)
    }

    // MARK: Удаление

    @Test("Удаление разового дела удаляет и шаблон")
    func deleteSingle() throws {
        let occ = try #require(service.create(draft()))
        service.delete(occ)
        #expect(occ.deletedAt != nil)
        #expect(all(TaskSeriesRecord.self).allSatisfy { $0.deletedAt != nil })
        #expect(ops().contains { $0.type == .delete && $0.entity == .taskOccurrence })
    }

    @Test("Удаление одного выполнения повторяющегося дела оставляет серию")
    func deleteOneOfSeries() throws {
        let occ = try #require(service.create(draft(repeat: .weekly)))
        service.delete(occ)
        #expect(all(TaskSeriesRecord.self).allSatisfy { $0.deletedAt == nil })
        #expect(all(TaskOccurrenceRecord.self).filter { $0.deletedAt == nil }.count == 8)
    }

    @Test("Удаление серии убирает все выполнения")
    func deleteWholeSeries() throws {
        let occ = try #require(service.create(draft(repeat: .weekly)))
        service.deleteSeries(occ.seriesId)
        #expect(all(TaskOccurrenceRecord.self).allSatisfy { $0.deletedAt != nil })
    }

    // MARK: Чек-лист

    @Test("Чек-лист копируется в каждое выполнение, отметка — только в одном")
    func checklistPerOccurrence() throws {
        var d = draft(repeat: .weekly)
        d.checklist = ["Положить сменку", "Взять воду"]
        _ = try #require(service.create(d))
        let s = all(TaskOccurrenceRecord.self).sorted { $0.dueAt < $1.dueAt }
        let first = service.checklist(for: s[0])
        let second = service.checklist(for: s[1])
        #expect(first.count == 2 && second.count == 2)
        service.toggle(first[0])
        #expect(service.checklist(for: s[0])[0].isDone)
        #expect(!service.checklist(for: s[1])[0].isDone)
    }

    // MARK: Напоминания

    @Test("Напоминание за 30 минут планируется, выполненное снимается")
    func reminderLifecycle() async throws {
        let occ = try #require(service.create(draft(on: at(22, 18, 30))))
        await service.reminderTask?.value
        var scheduled = await fake.last
        #expect(scheduled.count == 1)
        #expect(scheduled[0].fireDate == at(22, 18, 0))
        #expect(scheduled[0].id == occ.id.uuidString)
        #expect(await fake.authorizationRequests == 1)

        service.complete(occ)
        await service.reminderTask?.value
        scheduled = await fake.last
        #expect(scheduled.isEmpty)
    }

    @Test("Перенос обновляет напоминание без дублей")
    func reminderMovesWithReschedule() async throws {
        let occ = try #require(service.create(draft(on: at(22, 18, 30))))
        service.reschedule(occ, to: at(23, 9, 0), hasTime: true)
        await service.reminderTask?.value
        let scheduled = await fake.last
        #expect(scheduled.count == 1)
        #expect(scheduled[0].fireDate == at(23, 8, 30))
    }

    @Test("Без времени, прошедшее и чужое напоминания не планируются")
    func reminderFilters() async throws {
        var noTime = draft("Без времени", on: at(23))
        noTime.hasTime = false
        _ = service.create(noTime)
        _ = service.create(draft("Прошло", on: at(22, 12, 10)))   // срок через 10 минут, напоминание уже в прошлом
        var foreign = draft("Чужое", on: at(24))
        foreign.assigneeId = other
        _ = service.create(foreign)
        await service.reminderTask?.value
        #expect(await fake.last.isEmpty)
    }

    // MARK: Формат

    @Test("Дательный падеж имён")
    func dativeNames() {
        #expect(RussianNames.dative("Соня") == "Соне")
        #expect(RussianNames.dative("Анна") == "Анне")
        #expect(RussianNames.dative("Михаил") == "Михаилу")
        #expect(RussianNames.dative("Мария") == "Марии")
        #expect(RussianNames.dative("Андрей") == "Андрею")
    }

    @Test("Русские формулировки дат")
    func dateWording() {
        #expect(RussianDate.onThisWeekday(at(24), calendar: calendar) == "на эту субботу")
        #expect(RussianDate.onThisWeekday(at(22), calendar: calendar) == "на этот четверг")
        #expect(RussianDate.dayMonth(at(24), calendar: calendar) == "24 октября")
        #expect(Recurrence.weekly.title(for: at(22), calendar: calendar) == "Каждый четверг")
        #expect(Recurrence.monthly.title(for: at(22), calendar: calendar) == "Каждое 22-е число")
    }
}
