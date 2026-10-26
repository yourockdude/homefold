import Foundation
import SwiftData
import UIKit

/// Вымышленные данные семьи Смирновых для локальной разработки и скриншотов.
/// Включается аргументом запуска `-RYDemo`; в Release недоступно.
public enum DemoData {
    #if DEBUG
    /// Принудительное состояние обзора для проверки макетов: -RYOverviewLoading / -RYOverviewOffline / -RYOverviewError.
    static var overviewState: OverviewLoadState? {
        let args = ProcessInfo.processInfo.arguments
        let syncedAt = Calendar.current.date(bySettingHour: 9, minute: 36, second: 0, of: .now)
        if args.contains("-RYOverviewLoading") { return .loading }
        if args.contains("-RYOverviewOffline") { return .offline(lastSync: syncedAt) }
        if args.contains("-RYOverviewError") { return .failed(lastSync: syncedAt) }
        return nil
    }

    public static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-RYDemo") }

    /// Нарисованное фото для проверки аватаров: градиент и «солнце».
    static func sampleAvatar(hue: CGFloat) -> Data? {
        let size = CGSize(width: 600, height: 400)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor,
                          UIColor(hue: hue + 0.12, saturation: 0.7, brightness: 0.6, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor.white.withAlphaComponent(0.85).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 230, y: 90, width: 140, height: 140))
            ctx.cgContext.fillEllipse(in: CGRect(x: 170, y: 250, width: 260, height: 200))
        }
        return image.jpegData(compressionQuality: 0.9).flatMap(AvatarImage.prepare)
    }

    /// Состояние монетизации для демо: по умолчанию пробный период только начался.
    /// `-RYTrialDaysLeft N` (N = 0 — уже закончился) и `-RYSubscribed` для проверки экранов.
    static func applyTrialArguments(to family: FamilyRecord) {
        let args = ProcessInfo.processInfo.arguments
        let day: TimeInterval = 86_400
        if args.contains("-RYSubscribed") { family.plan = "plus"; family.trialStartedAt = .now.addingTimeInterval(-30 * day); return }
        if let index = args.firstIndex(of: "-RYTrialDaysLeft"), index + 1 < args.count, let left = Int(args[index + 1]) {
            let elapsed = Double(Monetization.trialDays - min(max(left, 0), Monetization.trialDays))
            family.trialStartedAt = left <= 0 ? .now.addingTimeInterval(-(Double(Monetization.trialDays) + 1) * day)
                                              : .now.addingTimeInterval(-elapsed * day - 3_600)
            return
        }
        family.trialStartedAt = .now
    }

    @MainActor
    public static func seed(into context: ModelContext) {
        let familyId = UUID()
        let anna = UUID(), mikhail = UUID(), sonya = UUID()
        let family = FamilyRecord(id: familyId, name: "Смирновы")
        applyTrialArguments(to: family)
        context.insert(family)
        context.insert(MemberRecord(id: anna, familyId: familyId, displayName: "Анна", role: "admin", toneIndex: 0))
        context.insert(MemberRecord(id: mikhail, familyId: familyId, displayName: "Михаил", role: "member", toneIndex: 1))
        context.insert(MemberRecord(id: sonya, familyId: familyId, displayName: "Соня", role: "member", toneIndex: 2))
        if ProcessInfo.processInfo.arguments.contains("-RYDemoAvatars"),
           let members = try? context.fetch(FetchDescriptor<MemberRecord>()) {
            for member in members where member.displayName != "Соня" {
                member.avatarData = sampleAvatar(hue: member.displayName == "Анна" ? 0.02 : 0.58)
            }
        }

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
        for i in items where !ProcessInfo.processInfo.arguments.contains("-RYEmptyShopping") {
            let r = ShoppingItemRecord(familyId: familyId, listId: list.id, authorId: i.0 == "Яблоки" ? mikhail : anna, name: i.0,
                                       quantity: i.1, unit: i.2, category: i.3, assigneeId: i.5, note: i.4)
            r.isBought = i.6
            if i.0 == "Яблоки" {   // последнее обновление покупок сделал другой участник — для подписи на «Обзоре»
                r.updatedAt = Date.now.addingTimeInterval(-5 * 60)
            }
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

        DemoDocuments.seed(into: context, store: DocumentFileStore(), familyId: familyId,
                           anna: anna, mikhail: mikhail, sonya: sonya)
        for r in (try? context.fetch(FetchDescriptor<ShoppingItemRecord>())) ?? [] { r.syncStatus = .synced }
        for r in (try? context.fetch(FetchDescriptor<ShoppingListRecord>())) ?? [] { r.syncStatus = .synced }
        for r in (try? context.fetch(FetchDescriptor<TaskSeriesRecord>())) ?? [] { r.syncStatus = .synced }
        for r in (try? context.fetch(FetchDescriptor<TaskOccurrenceRecord>())) ?? [] { r.syncStatus = .synced }
        for r in (try? context.fetch(FetchDescriptor<ChecklistItemRecord>())) ?? [] { r.syncStatus = .synced }
        try? context.save()
    }
    #endif
}
