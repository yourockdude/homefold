import Foundation
import SwiftData

/// Данные формы дела.
public struct TaskDraft: Equatable, Sendable {
    public var title = ""
    public var assigneeId: UUID?
    /// Дата и (если `hasTime`) время начала.
    public var start: Date
    public var hasTime = true
    public var recurrence = Recurrence.none
    /// Минуты до срока; nil — без напоминания.
    public var reminderMinutes: Int? = 30
    public var place = ""
    public var note = ""
    public var tag = ""
    /// Чек-лист нового дела. Для существующих дел пункты правятся в карточке.
    public var checklist: [String] = []

    public init(start: Date) { self.start = start }

    public init(occurrence: TaskOccurrenceRecord, recurrence: Recurrence) {
        title = occurrence.title
        assigneeId = occurrence.assigneeId
        start = occurrence.dueAt
        hasTime = occurrence.hasTime
        self.recurrence = recurrence
        reminderMinutes = occurrence.reminderMinutes
        place = occurrence.place
        note = occurrence.note
        tag = occurrence.tag
    }

    public enum Problem: Equatable, Sendable { case emptyTitle }

    public var problem: Problem? {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .emptyTitle : nil
    }
}

struct TaskSeriesPayload: Codable {
    var id: UUID
    var title: String
    var assigneeId: UUID?
    var place: String
    var note: String
    var startDate: Date
    var hasTime: Bool
    var recurrence: String
    var reminderMinutes: Int?
    var tag: String
    var checklistTemplate: [String]
}

struct TaskOccurrencePayload: Codable {
    var id: UUID
    var seriesId: UUID
    var title: String
    var assigneeId: UUID?
    var place: String
    var note: String
    var dueAt: Date
    var hasTime: Bool
    var reminderMinutes: Int?
    var tag: String
    var completedAt: Date?
    var completedById: UUID?
    var isDetached: Bool
}

struct ChecklistPayload: Codable {
    var id: UUID
    var occurrenceId: UUID
    var title: String
    var isDone: Bool
    var position: Int
}

/// Локальные действия над семейными делами. Меняют SwiftData, кладут операции в очередь
/// и пересобирают локальные напоминания.
@MainActor
public final class TaskService {
    private let context: ModelContext
    private let familyId: UUID
    private let userId: UUID
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let reminders: any ReminderScheduling
    /// Последнее запланированное обновление напоминаний — в тестах его можно дождаться.
    public private(set) var reminderTask: Task<Void, Never>?

    public init(context: ModelContext, familyId: UUID, userId: UUID,
                calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() },
                reminders: any ReminderScheduling = NoopReminderScheduler()) {
        self.context = context
        self.familyId = familyId
        self.userId = userId
        self.calendar = calendar
        self.now = now
        self.reminders = reminders
    }

    // MARK: Создание

    /// Создаёт дело (серию и её выполнения). Возвращает ближайшее выполнение.
    @discardableResult
    public func create(_ draft: TaskDraft) -> TaskOccurrenceRecord? {
        guard draft.problem == nil else { return nil }
        let series = TaskSeriesRecord(
            familyId: familyId, authorId: userId, title: clean(draft.title), assigneeId: draft.assigneeId,
            place: clean(draft.place), note: clean(draft.note), startDate: draft.start, hasTime: draft.hasTime,
            recurrence: draft.recurrence, reminderMinutes: draft.hasTime ? draft.reminderMinutes : nil,
            tag: clean(draft.tag), checklistTemplate: draft.checklist.map(clean).filter { !$0.isEmpty })
        context.insert(series)
        enqueueSeries(series)
        let created = materialize(series, from: draft.start, reviveTombstoned: true)
        save()
        refreshReminders(askPermission: series.reminderMinutes != nil)
        return created.first
    }

    /// Достраивает выполнения повторяющихся дел до горизонта. Безопасно вызывать сколько угодно раз.
    public func extendHorizon() {
        let descriptor = FetchDescriptor<TaskSeriesRecord>(
            predicate: #Predicate { $0.deletedAt == nil && $0.recurrenceRaw != "none" })
        for series in (try? context.fetch(descriptor)) ?? [] where series.familyId == familyId {
            materialize(series, from: series.startDate, reviveTombstoned: false)
        }
        save()
        refreshReminders()
    }

    // MARK: Правка

    /// Меняет только это выполнение. Остальные выполнения серии не затрагиваются.
    @discardableResult
    public func update(_ occurrence: TaskOccurrenceRecord, with draft: TaskDraft) -> Bool {
        guard draft.problem == nil, occurrence.deletedAt == nil else { return false }
        apply(draft, to: occurrence)
        occurrence.isDetached = true
        touch(occurrence)
        enqueueOccurrence(occurrence)
        save()
        refreshReminders(askPermission: occurrence.reminderMinutes != nil)
        return true
    }

    /// Явная правка серии: это и все следующие невыполненные выполнения, которые не правили отдельно.
    /// Выполненные, прошлые и отдельно изменённые выполнения остаются как есть.
    @discardableResult
    public func updateSeries(from occurrence: TaskOccurrenceRecord, with draft: TaskDraft) -> Bool {
        guard draft.problem == nil, occurrence.deletedAt == nil, let series = series(occurrence.seriesId) else { return false }
        series.title = clean(draft.title)
        series.assigneeId = draft.assigneeId
        series.place = clean(draft.place)
        series.note = clean(draft.note)
        series.tag = clean(draft.tag)
        series.hasTime = draft.hasTime
        series.reminderMinutes = draft.hasTime ? draft.reminderMinutes : nil
        series.recurrence = draft.recurrence
        series.startDate = draft.start
        series.updatedAt = now()
        series.syncStatus = .pending
        enqueueSeries(series)

        let anchor = occurrence.dueAt
        let inScope = occurrences(of: series.id).filter {
            $0.deletedAt == nil && !$0.isCompleted && !$0.isDetached && $0.dueAt >= anchor
        }
        let horizon = max(draft.start, now()).addingTimeInterval(TimeInterval(RecurrenceEngine.horizonDays) * 86_400)
        let targets = RecurrenceEngine.dates(start: draft.start, recurrence: draft.recurrence, until: horizon, calendar: calendar)
        let targetKeys = Set(targets.map(dayKey))
        for old in inScope where !targetKeys.contains(dayKey(old.dueAt)) { tombstone(old) }
        let existingByDay = Dictionary(grouping: occurrences(of: series.id).filter { $0.deletedAt == nil }, by: { dayKey($0.dueAt) })
        for date in targets {
            let key = dayKey(date)
            if let existing = existingByDay[key]?.first {
                guard inScope.contains(where: { $0.id == existing.id }) else { continue }
                apply(draft, to: existing, dueAt: date)
                existing.isDetached = false
                touch(existing)
                enqueueOccurrence(existing)
            } else {
                insertOccurrence(series: series, date: date, reviveTombstoned: true)
            }
        }
        save()
        refreshReminders(askPermission: series.reminderMinutes != nil)
        return true
    }

    // MARK: Состояние

    public func complete(_ occurrence: TaskOccurrenceRecord) {
        guard occurrence.deletedAt == nil, !occurrence.isCompleted else { return }
        occurrence.completedAt = now()
        occurrence.completedById = userId
        touch(occurrence)
        enqueueOccurrence(occurrence)
        save()
        refreshReminders()
    }

    /// Возвращает дело в работу. Остальная серия не затрагивается.
    public func reopen(_ occurrence: TaskOccurrenceRecord) {
        guard occurrence.deletedAt == nil, occurrence.isCompleted else { return }
        occurrence.completedAt = nil
        occurrence.completedById = nil
        touch(occurrence)
        enqueueOccurrence(occurrence)
        save()
        refreshReminders()
    }

    /// Переносит срок. Дело не становится выполненным, правка касается только этого выполнения.
    public func reschedule(_ occurrence: TaskOccurrenceRecord, to date: Date, hasTime: Bool) {
        guard occurrence.deletedAt == nil else { return }
        occurrence.dueAt = date
        occurrence.hasTime = hasTime
        if !hasTime { occurrence.reminderMinutes = nil }
        occurrence.isDetached = true
        touch(occurrence)
        enqueueOccurrence(occurrence)
        save()
        refreshReminders()
    }

    public func isOverdue(_ occurrence: TaskOccurrenceRecord) -> Bool {
        guard !occurrence.isCompleted, occurrence.deletedAt == nil else { return false }
        if occurrence.hasTime { return occurrence.dueAt < now() }
        return occurrence.dueAt < calendar.startOfDay(for: now())
    }

    // MARK: Удаление

    /// Удаляет только это выполнение. Для разового дела удаляется и сам шаблон.
    public func delete(_ occurrence: TaskOccurrenceRecord) {
        guard occurrence.deletedAt == nil else { return }
        tombstone(occurrence)
        if let series = series(occurrence.seriesId), series.recurrence == .none {
            tombstone(series)
        }
        save()
        refreshReminders()
    }

    /// Удаляет серию целиком вместе с выполнениями и историей.
    public func deleteSeries(_ seriesId: UUID) {
        guard let series = series(seriesId), series.deletedAt == nil else { return }
        for occurrence in occurrences(of: seriesId) where occurrence.deletedAt == nil { tombstone(occurrence) }
        tombstone(series)
        save()
        refreshReminders()
    }

    // MARK: Чек-лист

    public func checklist(for occurrence: TaskOccurrenceRecord) -> [ChecklistItemRecord] {
        let id = occurrence.id
        let descriptor = FetchDescriptor<ChecklistItemRecord>(
            predicate: #Predicate { $0.occurrenceId == id && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.position)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func toggle(_ item: ChecklistItemRecord) {
        guard item.deletedAt == nil else { return }
        item.isDone.toggle()
        touch(item)
        enqueueChecklist(item)
        save()
    }

    @discardableResult
    public func addChecklistItem(_ title: String, to occurrence: TaskOccurrenceRecord) -> ChecklistItemRecord? {
        let text = clean(title)
        guard !text.isEmpty else { return nil }
        let position = (checklist(for: occurrence).map(\.position).max() ?? -1) + 1
        let item = ChecklistItemRecord(familyId: familyId, occurrenceId: occurrence.id, title: text, position: position)
        context.insert(item)
        enqueueChecklist(item)
        save()
        return item
    }

    public func deleteChecklistItem(_ item: ChecklistItemRecord) {
        guard item.deletedAt == nil else { return }
        item.deletedAt = now()
        touch(item)
        enqueue(.checklistItem, id: item.id, .delete, version: item.version, EmptyBody())
        save()
    }

    // MARK: Напоминания

    /// Пересобирает локальные напоминания из базы. Вызывается после каждой правки, при возврате в
    /// приложение и при смене часового пояса или даты.
    public func reconcileReminders() async {
        await reminders.replaceAll(with: pendingReminders())
    }

    func pendingReminders() -> [TaskReminder] {
        let current = now()
        let descriptor = FetchDescriptor<TaskOccurrenceRecord>(
            predicate: #Predicate { $0.deletedAt == nil && $0.completedAt == nil && $0.hasTime })
        let list = ((try? context.fetch(descriptor)) ?? []).compactMap { occ -> TaskReminder? in
            guard occ.familyId == familyId, let minutes = occ.reminderMinutes,
                  occ.assigneeId == nil || occ.assigneeId == userId else { return nil }
            let fire = occ.dueAt.addingTimeInterval(-TimeInterval(minutes) * 60)
            guard fire > current else { return nil }
            return TaskReminder(id: occ.id.uuidString, title: occ.title,
                                body: Self.reminderBody(minutes: minutes, due: occ.dueAt, place: occ.place, calendar: calendar),
                                fireDate: fire)
        }
        return list.sorted { $0.fireDate < $1.fireDate }
    }

    static func reminderBody(minutes: Int, due: Date, place: String, calendar: Calendar) -> String {
        let lead: String
        switch minutes {
        case 0: lead = "Сейчас · \(RussianDate.time(due, calendar: calendar))"
        case 60: lead = "Через час · \(RussianDate.time(due, calendar: calendar))"
        case 1440: lead = "Завтра в \(RussianDate.time(due, calendar: calendar))"
        default: lead = "Через \(minutes) \(OverviewView.plural(minutes, "минуту", "минуты", "минут")) · \(RussianDate.time(due, calendar: calendar))"
        }
        let firstLine = place.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.isEmpty ? lead : "\(lead) · \(firstLine)"
    }

    private func refreshReminders(askPermission: Bool = false) {
        let scheduler = reminders
        let snapshot = pendingReminders()
        // Обновления идут строго по очереди, иначе старый снимок мог бы перезаписать новый.
        let previous = reminderTask
        reminderTask = Task {
            await previous?.value
            if askPermission { _ = await scheduler.requestAuthorizationIfNeeded() }
            await scheduler.replaceAll(with: snapshot)
        }
    }

    // MARK: Внутреннее

    private struct EmptyBody: Codable {}

    private func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func series(_ id: UUID) -> TaskSeriesRecord? {
        let descriptor = FetchDescriptor<TaskSeriesRecord>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    private func occurrences(of seriesId: UUID) -> [TaskOccurrenceRecord] {
        let descriptor = FetchDescriptor<TaskOccurrenceRecord>(
            predicate: #Predicate { $0.seriesId == seriesId }, sortBy: [SortDescriptor(\.dueAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func occurrence(id: UUID) -> TaskOccurrenceRecord? {
        let descriptor = FetchDescriptor<TaskOccurrenceRecord>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    /// Создаёт недостающие выполнения серии. Удалённые выполнения не воскрешаются.
    @discardableResult
    private func materialize(_ series: TaskSeriesRecord, from start: Date, reviveTombstoned: Bool) -> [TaskOccurrenceRecord] {
        let horizon = max(start, now()).addingTimeInterval(TimeInterval(RecurrenceEngine.horizonDays) * 86_400)
        let dates = RecurrenceEngine.dates(start: start, recurrence: series.recurrence, until: horizon, calendar: calendar)
        var created: [TaskOccurrenceRecord] = []
        for date in dates {
            if let made = insertOccurrence(series: series, date: date, reviveTombstoned: reviveTombstoned) { created.append(made) }
        }
        return created
    }

    @discardableResult
    private func insertOccurrence(series: TaskSeriesRecord, date: Date, reviveTombstoned: Bool) -> TaskOccurrenceRecord? {
        var id = DeterministicUUID.make(namespace: series.id, name: dayKey(date))
        if let existing = occurrence(id: id) {
            if existing.deletedAt == nil { return nil }
            // Удалённое выполнение не воскрешаем; при явной правке серии берём новый идентификатор.
            guard reviveTombstoned else { return nil }
            id = UUID()
        }
        let occ = TaskOccurrenceRecord(
            id: id, familyId: familyId, seriesId: series.id, authorId: series.authorId, title: series.title,
            assigneeId: series.assigneeId, place: series.place, note: series.note, dueAt: date,
            hasTime: series.hasTime, reminderMinutes: series.reminderMinutes, tag: series.tag)
        context.insert(occ)
        enqueueOccurrence(occ)
        for (index, title) in series.checklistTemplate.enumerated() {
            let item = ChecklistItemRecord(
                id: DeterministicUUID.make(namespace: occ.id, name: "chk-\(index)"),
                familyId: familyId, occurrenceId: occ.id, title: title, position: index)
            context.insert(item)
            enqueueChecklist(item)
        }
        return occ
    }

    private func apply(_ draft: TaskDraft, to occurrence: TaskOccurrenceRecord, dueAt: Date? = nil) {
        occurrence.title = clean(draft.title)
        occurrence.assigneeId = draft.assigneeId
        occurrence.place = clean(draft.place)
        occurrence.note = clean(draft.note)
        occurrence.tag = clean(draft.tag)
        occurrence.hasTime = draft.hasTime
        occurrence.reminderMinutes = draft.hasTime ? draft.reminderMinutes : nil
        occurrence.dueAt = dueAt ?? draft.start
    }

    private func tombstone(_ occurrence: TaskOccurrenceRecord) {
        occurrence.deletedAt = now()
        touch(occurrence)
        enqueue(.taskOccurrence, id: occurrence.id, .delete, version: occurrence.version, EmptyBody())
        for item in checklist(for: occurrence) { item.deletedAt = now() }
    }

    private func tombstone(_ series: TaskSeriesRecord) {
        series.deletedAt = now()
        series.updatedAt = now()
        series.syncStatus = .pending
        enqueue(.taskSeries, id: series.id, .delete, version: series.version, EmptyBody())
    }

    private func touch(_ occurrence: TaskOccurrenceRecord) { occurrence.updatedAt = now(); occurrence.syncStatus = .pending }
    private func touch(_ item: ChecklistItemRecord) { item.updatedAt = now(); item.syncStatus = .pending }

    private func enqueueSeries(_ s: TaskSeriesRecord) {
        enqueue(.taskSeries, id: s.id, .upsert, version: s.version,
                TaskSeriesPayload(id: s.id, title: s.title, assigneeId: s.assigneeId, place: s.place, note: s.note,
                                  startDate: s.startDate, hasTime: s.hasTime, recurrence: s.recurrenceRaw,
                                  reminderMinutes: s.reminderMinutes, tag: s.tag, checklistTemplate: s.checklistTemplate))
    }

    private func enqueueOccurrence(_ o: TaskOccurrenceRecord) {
        enqueue(.taskOccurrence, id: o.id, .upsert, version: o.version,
                TaskOccurrencePayload(id: o.id, seriesId: o.seriesId, title: o.title, assigneeId: o.assigneeId,
                                      place: o.place, note: o.note, dueAt: o.dueAt, hasTime: o.hasTime,
                                      reminderMinutes: o.reminderMinutes, tag: o.tag, completedAt: o.completedAt,
                                      completedById: o.completedById, isDetached: o.isDetached))
    }

    private func enqueueChecklist(_ c: ChecklistItemRecord) {
        enqueue(.checklistItem, id: c.id, .upsert, version: c.version,
                ChecklistPayload(id: c.id, occurrenceId: c.occurrenceId, title: c.title, isDone: c.isDone, position: c.position))
    }

    @discardableResult
    private func enqueue<P: Encodable>(_ entity: SyncEntity, id: UUID, _ type: SyncOperationType, version: Int, _ payload: P) -> OutboxOperation {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let op = OutboxOperation(entity: entity, entityId: id, type: type, baseVersion: version,
                                 payload: (try? encoder.encode(payload)) ?? Data())
        context.insert(op)
        return op
    }

    private func save() {
        do { try context.save() } catch { assertionFailure("Не удалось сохранить: \(error)") }
    }
}
