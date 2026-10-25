import Testing
import Foundation
import SwiftData
@testable import RyadomFeature

@MainActor
struct ShoppingServiceTests {
    let context: ModelContext
    let service: ShoppingService
    let family = UUID()
    let user = UUID()

    init() {
        context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
        service = ShoppingService(context: context, familyId: family, userId: user)
    }

    private func draft(_ name: String, qty: Double = 1) -> ShoppingItemDraft {
        var d = ShoppingItemDraft()
        d.name = name
        d.quantity = qty
        return d
    }

    private func outbox() -> [OutboxOperation] {
        ((try? context.fetch(FetchDescriptor<OutboxOperation>())) ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    @Test("Пустое название и нулевое количество отклоняются")
    func validation() {
        let list = service.activeList()
        #expect(service.add(draft("  "), to: list) == nil)
        #expect(service.add(draft("Хлеб", qty: 0), to: list) == nil)
        #expect(draft(" ").problem == .emptyName)
        #expect(draft("Хлеб", qty: -1).problem == .invalidQuantity)
    }

    @Test("Добавление кладёт товар в базу и операцию в очередь")
    func addEnqueues() throws {
        let list = service.activeList()
        let item = try #require(service.add(draft("Молоко", qty: 2), to: list))
        #expect(item.syncStatus == .pending)
        let ops = outbox().filter { $0.entityId == item.id }
        #expect(ops.count == 1)
        #expect(ops.first?.type == .upsert)
    }

    @Test("activeList не создаёт дубликатов")
    func singleActiveList() {
        let a = service.activeList()
        let b = service.activeList()
        #expect(a.id == b.id)
    }

    @Test("Покупка и возврат товара")
    func toggleBought() throws {
        let item = try #require(service.add(draft("Яйца"), to: service.activeList()))
        service.setBought(item, true)
        #expect(item.isBought)
        service.setBought(item, false)
        #expect(!item.isBought)
    }

    @Test("Отмена удаления до отправки снимает операцию")
    func undoBeforeSend() throws {
        let item = try #require(service.add(draft("Кофе"), to: service.activeList()))
        service.delete(item)
        #expect(item.deletedAt != nil)
        #expect(outbox().contains { $0.entityId == item.id && $0.type == .delete })
        let restored = try #require(service.undoDelete(item))
        #expect(restored.id == item.id)
        #expect(item.deletedAt == nil)
        #expect(!outbox().contains { $0.entityId == item.id && $0.type == .delete })
    }

    @Test("Отмена удаления после отправки создаёт новую запись")
    func undoAfterSend() throws {
        let item = try #require(service.add(draft("Кофе"), to: service.activeList()))
        service.delete(item)
        let op = try #require(outbox().first { $0.type == .delete })
        op.attempts = 1
        let restored = try #require(service.undoDelete(item))
        #expect(restored.id != item.id)
        #expect(restored.name == "Кофе")
    }

    @Test("Очистка купленного удаляет только купленное")
    func clearBought() throws {
        let list = service.activeList()
        let a = try #require(service.add(draft("A"), to: list))
        let b = try #require(service.add(draft("B"), to: list))
        service.setBought(a, true)
        #expect(service.clearBought(in: list) == 1)
        #expect(a.deletedAt != nil)
        #expect(b.deletedAt == nil)
    }

    @Test("Новый список архивирует текущий")
    func newList() throws {
        let old = service.activeList()
        _ = service.add(draft("A"), to: old)
        let fresh = service.startNewList()
        #expect(old.isArchived)
        #expect(!fresh.isArchived)
        #expect(service.activeList().id == fresh.id)
    }

    @Test("Русские формы числительных")
    func plurals() {
        #expect(OverviewViewPlural.f(1) == "товар")
        #expect(OverviewViewPlural.f(3) == "товара")
        #expect(OverviewViewPlural.f(5) == "товаров")
        #expect(OverviewViewPlural.f(11) == "товаров")
        #expect(OverviewViewPlural.f(22) == "товара")
    }
}

enum OverviewViewPlural {
    static func f(_ n: Int) -> String { ShoppingFormatBridge.goods(n) }
}
