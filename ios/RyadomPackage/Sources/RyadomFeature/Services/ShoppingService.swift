import Foundation
import SwiftData

public enum ShoppingCategory: String, CaseIterable, Sendable {
    case dairy = "Молочное и яйца"
    case produce = "Овощи и фрукты"
    case meat = "Мясо и рыба"
    case bakery = "Выпечка"
    case pantry = "Бакалея"
    case household = "Дом и быт"
    case other = "Остальное"
}

public enum ShoppingUnit: String, CaseIterable, Sendable {
    case piece = "шт."
    case gram = "г"
    case kilogram = "кг"
    case liter = "л"
    case milliliter = "мл"
    case pack = "уп."

    /// Шаг кнопок «+» и «−».
    public var step: Double {
        switch self {
        case .piece, .pack: 1
        case .gram, .milliliter: 50
        case .kilogram, .liter: 0.5
        }
    }
}

/// Данные формы товара.
public struct ShoppingItemDraft: Equatable, Sendable {
    public var name = ""
    public var quantity: Double = 1
    public var unit = ShoppingUnit.piece.rawValue
    public var category = ShoppingCategory.other.rawValue
    public var assigneeId: UUID?
    public var note = ""

    public init() {}

    public init(_ item: ShoppingItemRecord) {
        name = item.name
        quantity = item.quantity
        unit = item.unit
        category = item.category
        assigneeId = item.assigneeId
        note = item.note
    }

    public enum Problem: Equatable, Sendable {
        case emptyName
        case invalidQuantity
    }

    public var problem: Problem? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyName }
        if !(quantity > 0) { return .invalidQuantity }
        return nil
    }
}

/// Тело операции синхронизации для товара.
struct ShoppingItemPayload: Codable {
    var id: UUID
    var listId: UUID
    var name: String
    var quantity: Double
    var unit: String
    var category: String
    var assigneeId: UUID?
    var note: String
    var isBought: Bool
}

struct ShoppingListPayload: Codable {
    var id: UUID
    var title: String
    var isArchived: Bool
}

/// Локальные действия над списком покупок. Каждое действие сначала меняет SwiftData,
/// затем кладёт операцию в очередь `OutboxOperation` — её отправит `SyncEngine`.
@MainActor
public final class ShoppingService {
    /// Задержка перед отправкой удаления: пока она не истекла, удаление можно отменить.
    public static let undoWindow: TimeInterval = 6

    private let context: ModelContext
    private let familyId: UUID
    private let userId: UUID

    public init(context: ModelContext, familyId: UUID, userId: UUID) {
        self.context = context
        self.familyId = familyId
        self.userId = userId
    }

    // MARK: Списки

    /// Активный список; создаётся, если его ещё нет.
    @discardableResult
    public func activeList() -> ShoppingListRecord {
        let fid = familyId
        let descriptor = FetchDescriptor<ShoppingListRecord>(
            predicate: #Predicate { $0.familyId == fid && !$0.isArchived && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let list = ShoppingListRecord(familyId: familyId, authorId: userId)
        context.insert(list)
        enqueue(.shoppingList, id: list.id, .upsert, version: list.version,
                ShoppingListPayload(id: list.id, title: list.title, isArchived: false))
        save()
        return list
    }

    /// Переносит текущий список в историю и создаёт новый.
    @discardableResult
    public func startNewList() -> ShoppingListRecord {
        let current = activeList()
        current.isArchived = true
        touch(current)
        enqueue(.shoppingList, id: current.id, .upsert, version: current.version,
                ShoppingListPayload(id: current.id, title: current.title, isArchived: true))
        let fresh = ShoppingListRecord(familyId: familyId, authorId: userId)
        context.insert(fresh)
        enqueue(.shoppingList, id: fresh.id, .upsert, version: fresh.version,
                ShoppingListPayload(id: fresh.id, title: fresh.title, isArchived: false))
        save()
        return fresh
    }

    // MARK: Товары

    @discardableResult
    public func add(_ draft: ShoppingItemDraft, to list: ShoppingListRecord) -> ShoppingItemRecord? {
        guard draft.problem == nil else { return nil }
        let item = ShoppingItemRecord(
            familyId: familyId, listId: list.id, authorId: userId,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: draft.quantity, unit: draft.unit, category: draft.category,
            assigneeId: draft.assigneeId,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(item)
        enqueueUpsert(item)
        save()
        return item
    }

    @discardableResult
    public func update(_ item: ShoppingItemRecord, with draft: ShoppingItemDraft) -> Bool {
        guard draft.problem == nil, item.deletedAt == nil else { return false }
        item.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = draft.quantity
        item.unit = draft.unit
        item.category = draft.category
        item.assigneeId = draft.assigneeId
        item.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        touch(item)
        enqueueUpsert(item)
        save()
        return true
    }

    public func setBought(_ item: ShoppingItemRecord, _ bought: Bool) {
        guard item.deletedAt == nil, item.isBought != bought else { return }
        item.isBought = bought
        touch(item)
        enqueueUpsert(item)
        save()
    }

    /// Мягкое удаление с возможностью отмены в течение `undoWindow`.
    public func delete(_ item: ShoppingItemRecord) {
        guard item.deletedAt == nil else { return }
        item.deletedAt = .now
        touch(item)
        let op = enqueue(.shoppingItem, id: item.id, .delete, version: item.version, EmptyPayload())
        op.nextAttemptAt = Date.now.addingTimeInterval(Self.undoWindow)
        save()
    }

    /// Отменяет удаление. Если операция ещё не ушла на сервер — просто снимает её,
    /// иначе возвращает товар как новую запись (сервер не воскрешает удалённое).
    @discardableResult
    public func undoDelete(_ item: ShoppingItemRecord) -> ShoppingItemRecord? {
        guard item.deletedAt != nil else { return nil }
        let id = item.id
        let descriptor = FetchDescriptor<OutboxOperation>(
            predicate: #Predicate { $0.entityId == id && $0.typeRaw == "delete" }
        )
        if let pending = (try? context.fetch(descriptor))?.first(where: { $0.attempts == 0 && $0.nextAttemptAt > .now }) {
            context.delete(pending)
            item.deletedAt = nil
            touch(item)
            save()
            return item
        }
        var draft = ShoppingItemDraft(item)
        draft.note = item.note
        let restored = ShoppingItemRecord(familyId: familyId, listId: item.listId, authorId: userId, name: draft.name,
                                          quantity: draft.quantity, unit: draft.unit, category: draft.category,
                                          assigneeId: draft.assigneeId, note: draft.note)
        restored.isBought = item.isBought
        context.insert(restored)
        enqueueUpsert(restored)
        save()
        return restored
    }

    /// Удаляет все купленные товары списка (без отмены — подтверждается диалогом).
    @discardableResult
    public func clearBought(in list: ShoppingListRecord) -> Int {
        let lid = list.id
        let descriptor = FetchDescriptor<ShoppingItemRecord>(
            predicate: #Predicate { $0.listId == lid && $0.isBought && $0.deletedAt == nil }
        )
        let bought = (try? context.fetch(descriptor)) ?? []
        for item in bought {
            item.deletedAt = .now
            touch(item)
            enqueue(.shoppingItem, id: item.id, .delete, version: item.version, EmptyPayload())
        }
        save()
        return bought.count
    }

    // MARK: Внутреннее

    private struct EmptyPayload: Codable {}

    private func touch(_ item: ShoppingItemRecord) {
        item.updatedAt = .now
        item.syncStatus = .pending
    }

    private func touch(_ list: ShoppingListRecord) {
        list.updatedAt = .now
        list.syncStatus = .pending
    }

    private func enqueueUpsert(_ item: ShoppingItemRecord) {
        enqueue(.shoppingItem, id: item.id, .upsert, version: item.version,
                ShoppingItemPayload(id: item.id, listId: item.listId, name: item.name, quantity: item.quantity,
                                    unit: item.unit, category: item.category, assigneeId: item.assigneeId,
                                    note: item.note, isBought: item.isBought))
    }

    @discardableResult
    private func enqueue<P: Encodable>(_ entity: SyncEntity, id: UUID, _ type: SyncOperationType,
                                       version: Int, _ payload: P) -> OutboxOperation {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(payload)) ?? Data()
        let op = OutboxOperation(entity: entity, entityId: id, type: type, baseVersion: version, payload: data)
        context.insert(op)
        return op
    }

    private func save() {
        do { try context.save() } catch { assertionFailure("Не удалось сохранить: \(error)") }
    }
}
