import Foundation
import SwiftData

public enum Recurrence: String, Codable, CaseIterable, Sendable {
    case none, daily, weekly, monthly

    public var title: String {
        switch self {
        case .none: "Без повтора"
        case .daily: "Ежедневно"
        case .weekly: "Еженедельно"
        case .monthly: "Ежемесячно"
        }
    }
}

/// Шаблон дела. Для разового дела серия содержит ровно одно выполнение.
@Model
public final class TaskSeriesRecord {
    @Attribute(.unique) public var id: UUID
    public var familyId: UUID
    public var authorId: UUID
    public var title: String
    public var assigneeId: UUID?
    public var place: String
    public var note: String
    public var startDate: Date
    public var hasTime: Bool
    public var recurrenceRaw: String
    /// Минуты до начала; nil — без напоминания.
    public var reminderMinutes: Int?
    /// Метка дела («Дети», «Дом»…); пустая строка — без метки.
    public var tag: String = ""
    /// Пункты чек-листа, которые копируются в каждое выполнение.
    public var checklistTemplate: [String] = []
    public var createdAt: Date
    public var updatedAt: Date
    public var version: Int
    public var deletedAt: Date?
    public var syncStatusRaw: String

    public init(id: UUID = UUID(), familyId: UUID, authorId: UUID, title: String, assigneeId: UUID?,
                place: String = "", note: String = "", startDate: Date, hasTime: Bool,
                recurrence: Recurrence = .none, reminderMinutes: Int? = 30, tag: String = "",
                checklistTemplate: [String] = [], createdAt: Date = .now) {
        self.tag = tag
        self.checklistTemplate = checklistTemplate
        self.id = id
        self.familyId = familyId
        self.authorId = authorId
        self.title = title
        self.assigneeId = assigneeId
        self.place = place
        self.note = note
        self.startDate = startDate
        self.hasTime = hasTime
        self.recurrenceRaw = recurrence.rawValue
        self.reminderMinutes = reminderMinutes
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.version = 0
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    public var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    public var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
}

/// Конкретное выполнение дела. Правки и завершение касаются только его.
@Model
public final class TaskOccurrenceRecord {
    @Attribute(.unique) public var id: UUID
    public var familyId: UUID
    public var seriesId: UUID
    public var authorId: UUID
    public var title: String
    public var assigneeId: UUID?
    public var place: String
    public var note: String
    public var dueAt: Date
    public var hasTime: Bool
    public var reminderMinutes: Int?
    public var completedAt: Date?
    public var completedById: UUID?
    public var tag: String = ""
    /// Выполнение правили отдельно — правка серии его не трогает.
    public var isDetached: Bool = false
    public var createdAt: Date
    public var updatedAt: Date
    public var version: Int
    public var deletedAt: Date?
    public var syncStatusRaw: String

    public init(id: UUID = UUID(), familyId: UUID, seriesId: UUID, authorId: UUID, title: String,
                assigneeId: UUID?, place: String = "", note: String = "", dueAt: Date, hasTime: Bool,
                reminderMinutes: Int? = 30, tag: String = "", createdAt: Date = .now) {
        self.tag = tag
        self.id = id
        self.familyId = familyId
        self.seriesId = seriesId
        self.authorId = authorId
        self.title = title
        self.assigneeId = assigneeId
        self.place = place
        self.note = note
        self.dueAt = dueAt
        self.hasTime = hasTime
        self.reminderMinutes = reminderMinutes
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.version = 0
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    public var isCompleted: Bool { completedAt != nil }

    public var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
}

@Model
public final class ChecklistItemRecord {
    @Attribute(.unique) public var id: UUID
    public var familyId: UUID
    public var occurrenceId: UUID
    public var title: String
    public var isDone: Bool
    public var position: Int
    public var updatedAt: Date
    public var version: Int
    public var deletedAt: Date?
    public var syncStatusRaw: String

    public init(id: UUID = UUID(), familyId: UUID, occurrenceId: UUID, title: String, position: Int) {
        self.id = id
        self.familyId = familyId
        self.occurrenceId = occurrenceId
        self.title = title
        self.isDone = false
        self.position = position
        self.updatedAt = .now
        self.version = 0
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    public var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
}
