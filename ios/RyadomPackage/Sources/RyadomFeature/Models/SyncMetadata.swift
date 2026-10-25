import Foundation

/// Состояние синхронизации записи на клиенте.
public enum SyncStatus: String, Codable, Sendable {
    case synced
    case pending
    case failed
}

/// Типы синхронизируемых сущностей (совпадают с `entity` в `/sync/push`).
public enum SyncEntity: String, Codable, Sendable {
    case shoppingList, shoppingItem
    case taskSeries, taskOccurrence, checklistItem
    case document
    /// Операции над семьёй уходят на REST-эндпоинты `/families`, `/invitations`, а не в `/sync/push`.
    case family, member, invitation
}

public enum SyncOperationType: String, Codable, Sendable {
    case upsert, delete
}
