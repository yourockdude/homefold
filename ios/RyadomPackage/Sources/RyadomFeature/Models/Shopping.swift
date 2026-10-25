import Foundation
import SwiftData

@Model
public final class ShoppingListRecord {
    @Attribute(.unique) public var id: UUID
    public var familyId: UUID
    public var authorId: UUID
    public var title: String
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var version: Int
    public var deletedAt: Date?
    public var syncStatusRaw: String

    public init(id: UUID = UUID(), familyId: UUID, authorId: UUID, title: String = "Покупки",
                isArchived: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.familyId = familyId
        self.authorId = authorId
        self.title = title
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.version = 0
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    public var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
}

@Model
public final class ShoppingItemRecord {
    @Attribute(.unique) public var id: UUID
    public var familyId: UUID
    public var listId: UUID
    public var authorId: UUID
    public var name: String
    public var quantity: Double
    public var unit: String
    public var category: String
    /// nil — «Любой».
    public var assigneeId: UUID?
    public var note: String
    public var isBought: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var version: Int
    public var deletedAt: Date?
    public var syncStatusRaw: String

    public init(id: UUID = UUID(), familyId: UUID, listId: UUID, authorId: UUID, name: String,
                quantity: Double = 1, unit: String = "шт", category: String = "Другое",
                assigneeId: UUID? = nil, note: String = "", createdAt: Date = .now) {
        self.id = id
        self.familyId = familyId
        self.listId = listId
        self.authorId = authorId
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.assigneeId = assigneeId
        self.note = note
        self.isBought = false
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.version = 0
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    public var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
}
