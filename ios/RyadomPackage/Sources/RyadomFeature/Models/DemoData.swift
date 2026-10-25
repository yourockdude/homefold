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
        let items: [(String, Double, String, String, UUID?)] = [
            ("Молоко", 2, "л", "Молочное", nil), ("Яблоки", 1.5, "кг", "Овощи и фрукты", mikhail),
            ("Хлеб", 1, "шт", "Выпечка", nil), ("Сыр", 300, "г", "Молочное", anna),
            ("Помидоры", 1, "кг", "Овощи и фрукты", nil), ("Чай", 1, "уп", "Другое", sonya),
        ]
        for i in items {
            context.insert(ShoppingItemRecord(familyId: familyId, listId: list.id, authorId: anna, name: i.0,
                                              quantity: i.1, unit: i.2, category: i.3, assigneeId: i.4))
        }

        let cal = Calendar.current
        func today(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: .now) ?? .now }
        for (title, d, who) in [("Забрать Соню с танцев", today(18, 30), mikhail),
                                ("Полить растения", today(19, 0), sonya),
                                ("Оплатить интернет", today(21, 0), anna)] {
            let s = TaskSeriesRecord(familyId: familyId, authorId: anna, title: title, assigneeId: who, startDate: d, hasTime: true)
            context.insert(s)
            context.insert(TaskOccurrenceRecord(familyId: familyId, seriesId: s.id, authorId: anna, title: title,
                                                assigneeId: who, dueAt: d, hasTime: true))
        }

        let exp = cal.date(from: DateComponents(year: 2027, month: 8, day: 31))
        context.insert(DocumentRecord(familyId: familyId, authorId: anna, ownerId: sonya, title: "Полис ДМС · Соня",
                                      category: .health, expiresAt: exp, mimeType: "application/pdf",
                                      sizeBytes: 120_000, localFileName: nil))
        try? context.save()
    }
    #endif
}
