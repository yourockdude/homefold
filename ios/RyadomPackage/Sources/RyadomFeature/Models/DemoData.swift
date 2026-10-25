import Foundation
import SwiftData

/// Вымышленные данные семьи Смирновых для локальной разработки и скриншотов.
/// Включается аргументом запуска `-RYDemo`; в Release недоступно.
public enum DemoData {
    #if DEBUG
    public static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-RYDemo") }

    @MainActor
    public static func seed(into context: ModelContext) {
        let familyId = UUID()
        let anna = UUID(), mikhail = UUID(), sonya = UUID()
        context.insert(FamilyRecord(id: familyId, name: "Смирновы"))
        context.insert(MemberRecord(id: anna, familyId: familyId, displayName: "Анна", role: "admin", toneIndex: 0))
        context.insert(MemberRecord(id: mikhail, familyId: familyId, displayName: "Михаил", role: "member", toneIndex: 1))
        context.insert(MemberRecord(id: sonya, familyId: familyId, displayName: "Соня", role: "member", toneIndex: 2))

        let list = ShoppingListRecord(familyId: familyId, authorId: anna)
        context.insert(list)
        let items: [(String, Double, String, String, String, UUID?, Bool)] = [
            ("Молоко 3,2%", 2, "л", "Молочное и яйца", "Домик в деревне", anna, false),
            ("Яйца С1", 10, "шт.", "Молочное и яйца", "", anna, false),
            ("Яблоки", 1, "кг", "Овощи и фрукты", "зелёные", sonya, false),
            ("Помидоры", 500, "г", "Овощи и фрукты", "для салата", mikhail, false),
            ("Хлеб на закваске", 1, "шт.", "Остальное", "", anna, false),
            ("Кофе в зёрнах", 250, "г", "Остальное", "", mikhail, false),
            ("Йогурт", 1, "шт.", "Молочное и яйца", "", nil, true),
            ("Бананы", 1, "кг", "Овощи и фрукты", "", nil, true),
        ]
        for i in items {
            let r = ShoppingItemRecord(familyId: familyId, listId: list.id, authorId: anna, name: i.0,
                                       quantity: i.1, unit: i.2, category: i.3, assigneeId: i.5, note: i.4)
            r.isBought = i.6
            context.insert(r)
        }

        let cal = Calendar.current
        func at(_ day: Int, _ h: Int, _ m: Int) -> Date {
            let base = cal.date(byAdding: .day, value: day, to: .now) ?? .now
            return cal.date(bySettingHour: h, minute: m, second: 0, of: base) ?? base
        }
        let tasks = TaskService(context: context, familyId: familyId, userId: anna)
        func make(_ title: String, _ when: Date, who: UUID, tag: String, place: String = "", note: String = "",
                  repeat r: Recurrence = .none, checklist: [String] = []) -> TaskOccurrenceRecord? {
            var d = TaskDraft(start: when)
            d.title = title; d.assigneeId = who; d.tag = tag; d.place = place; d.note = note
            d.recurrence = r; d.checklist = checklist
            return tasks.create(d)
        }
        if let pickup = make("Забрать Соню с танцев", at(0, 18, 30), who: mikhail, tag: "Дети",
                             place: "Студия «Ритм»\nул. Лесная, 12 · вход со двора",
                             note: "Сменка уже в рюкзаке. После занятия Соня будет ждать у входа со двора.",
                             checklist: ["Положить сменку в рюкзак", "Взять бутылку воды"]),
           let first = tasks.checklist(for: pickup).first {
            tasks.toggle(first)
        }
        _ = make("Полить растения", at(0, 19, 0), who: sonya, tag: "Дом", note: "На кухне и в гостиной", repeat: .weekly)
        _ = make("Сверить показания счётчиков", at(0, 21, 0), who: anna, tag: "Дом")
        _ = make("Продлить страховку квартиры", at(-1, 21, 0), who: anna, tag: "Документы")
        if let paid = make("Оплатить интернет", at(0, 9, 0), who: mikhail, tag: "Дом", note: "Оплата прошла. Подтверждение сохранено у Михаила.",
                           checklist: ["Оплатить за ноябрь"]) {
            for item in tasks.checklist(for: paid) { tasks.toggle(item) }
            paid.completedAt = at(0, 8, 45)
            paid.completedById = mikhail
        }

        let exp = cal.date(from: DateComponents(year: 2027, month: 8, day: 31))
        context.insert(DocumentRecord(familyId: familyId, authorId: anna, ownerId: sonya, title: "Полис ДМС · Соня",
                                      category: .health, expiresAt: exp, mimeType: "application/pdf",
                                      sizeBytes: 120_000, localFileName: nil))
        for r in (try? context.fetch(FetchDescriptor<ShoppingItemRecord>())) ?? [] { r.syncStatus = .synced }
        for r in (try? context.fetch(FetchDescriptor<ShoppingListRecord>())) ?? [] { r.syncStatus = .synced }
        for r in (try? context.fetch(FetchDescriptor<TaskSeriesRecord>())) ?? [] { r.syncStatus = .synced }
        for r in (try? context.fetch(FetchDescriptor<TaskOccurrenceRecord>())) ?? [] { r.syncStatus = .synced }
        for r in (try? context.fetch(FetchDescriptor<ChecklistItemRecord>())) ?? [] { r.syncStatus = .synced }
        try? context.save()
    }
    #endif
}
