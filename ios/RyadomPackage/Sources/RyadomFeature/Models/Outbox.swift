import Foundation
import SwiftData

/// Операция в персистентной очереди. `id` — идемпотентный `opId`, уходит на сервер.
@Model
public final class OutboxOperation {
    @Attribute(.unique) public var id: UUID
    public var entityRaw: String
    public var entityId: UUID
    public var typeRaw: String
    public var baseVersion: Int
    public var payload: Data
    public var createdAt: Date
    public var attempts: Int
    public var nextAttemptAt: Date
    public var lastError: String?
    public var isFailed: Bool

    public init(entity: SyncEntity, entityId: UUID, type: SyncOperationType, baseVersion: Int, payload: Data) {
        self.id = UUID()
        self.entityRaw = entity.rawValue
        self.entityId = entityId
        self.typeRaw = type.rawValue
        self.baseVersion = baseVersion
        self.payload = payload
        self.createdAt = .now
        self.attempts = 0
        self.nextAttemptAt = .now
        self.isFailed = false
    }

    public var entity: SyncEntity { SyncEntity(rawValue: entityRaw) ?? .shoppingItem }
    public var type: SyncOperationType { SyncOperationType(rawValue: typeRaw) ?? .upsert }
}

/// Курсор получения изменений и время последней успешной синхронизации.
@Model
public final class SyncCursor {
    @Attribute(.unique) public var familyId: UUID
    public var cursor: String
    public var lastSyncAt: Date?

    public init(familyId: UUID, cursor: String = "0", lastSyncAt: Date? = nil) {
        self.familyId = familyId
        self.cursor = cursor
        self.lastSyncAt = lastSyncAt
    }
}
