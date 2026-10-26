import Foundation
import SwiftUI

/// Куда ведёт результат поиска.
public enum SearchDestination: Hashable, Sendable {
    case shoppingItem(UUID)
    case task(UUID)
    case document(UUID)
}

public enum SearchKind: Int, CaseIterable, Sendable {
    case tasks, shopping, documents

    public var title: String {
        switch self {
        case .tasks: "Дела"
        case .shopping: "Покупки"
        case .documents: "Документы"
        }
    }

    public var systemImage: String {
        switch self {
        case .tasks: "checkmark.circle"
        case .shopping: "basket"
        case .documents: "folder"
        }
    }
}

public struct SearchHit: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: SearchKind
    public let title: String
    public let subtitle: String
    public let destination: SearchDestination
    /// Выполнено или куплено — в списке выглядит приглушённым.
    public let isMuted: Bool
    let score: Int
}

public struct SearchSection: Identifiable, Equatable, Sendable {
    public let kind: SearchKind
    /// Все совпадения раздела, по убыванию релевантности.
    public let hits: [SearchHit]
    public var id: Int { kind.rawValue }
}

/// Сопоставление слов запроса с текстом без учёта регистра и «ё/е».
/// Если слово целиком не нашлось, пробуем его основу без последней буквы в начале слова:
/// «соня» → «Соню», «молоко» → «молока». Для коротких слов (меньше 4 букв) основа не используется.
public enum SearchMatcher {
    private static let locale = Locale(identifier: "ru_RU")
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Точное вхождение слова запроса.
    public static func range(of term: String, in text: String) -> Range<String.Index>? {
        guard !term.isEmpty else { return nil }
        return text.range(of: term, options: options, range: nil, locale: locale)
    }

    /// Совпадение по основе слова: начало слова в тексте.
    static func stemRange(of term: String, in text: String) -> Range<String.Index>? {
        guard term.count >= 4 else { return nil }
        let stem = String(term.dropLast())
        var searchStart = text.startIndex
        while let r = text.range(of: stem, options: options, range: searchStart..<text.endIndex, locale: locale) {
            if r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter { return r }
            searchStart = r.upperBound
        }
        return nil
    }

    /// 3 — слово начинается с запроса, 2 — совпадение в начале слова внутри строки или по основе слова,
    /// 1 — внутри слова, 0 — нет.
    static func weight(term: String, in text: String) -> Int {
        if let r = range(of: term, in: text) {
            if r.lowerBound == text.startIndex { return 3 }
            let before = text[text.index(before: r.lowerBound)]
            return before.isLetter || before.isNumber ? 1 : 2
        }
        return stemRange(of: term, in: text) == nil ? 0 : 2
    }

    /// Название с выделенными совпадениями.
    public static func highlighted(_ text: String, terms: [String], tint: Color) -> AttributedString {
        var result = AttributedString(text)
        for term in terms {
            guard let r = range(of: term, in: text) ?? stemRange(of: term, in: text),
                  let lower = AttributedString.Index(r.lowerBound, within: result),
                  let upper = AttributedString.Index(r.upperBound, within: result) else { continue }
            result[lower..<upper].foregroundColor = tint
            result[lower..<upper].font = .body.weight(.semibold)
        }
        return result
    }
}

/// Сквозной поиск по делам, покупкам и документам. Работает по локальной базе.
public enum GlobalSearch {
    /// Сколько результатов раздела показываем, пока его не раскрыли.
    public static let previewLimit = 4

    @MainActor
    public static func run(query: String,
                           tasks: [TaskOccurrenceRecord], checklist: [ChecklistItemRecord],
                           shopping: [ShoppingItemRecord], lists: [ShoppingListRecord],
                           documents: [DocumentRecord], members: [MemberRecord],
                           includeDocuments: Bool,
                           calendar: Calendar = .current, now: Date = .now) -> [SearchSection] {
        let terms = SearchMatcher.terms(query)
        guard !terms.isEmpty else { return [] }
        let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let checklistByTask = Dictionary(grouping: checklist.filter { $0.deletedAt == nil }, by: \.occurrenceId)
        let archivedLists = Set(lists.filter(\.isArchived).map(\.id))

        var sections: [SearchSection] = []

        let taskHits: [SearchHit] = tasks.filter { $0.deletedAt == nil }.compactMap { task in
            let assignee = task.assigneeId.flatMap { names[$0] } ?? ""
            let secondary = [task.place, task.note, task.tag, assignee] + (checklistByTask[task.id] ?? []).map(\.title)
            guard let score = score(terms: terms, primary: task.title, secondary: secondary) else { return nil }
            // Невыполненные выше выполненных, ближайшие по сроку выше дальних.
            let freshness = task.isCompleted ? 0 : max(0, 20 - abs(Int(task.dueAt.timeIntervalSince(now) / 86_400)))
            return SearchHit(id: "task-\(task.id)", kind: .tasks, title: task.title,
                             subtitle: taskSubtitle(task, assignee: assignee, calendar: calendar, now: now),
                             destination: .task(task.id), isMuted: task.isCompleted, score: score + freshness + (task.isCompleted ? 0 : 50))
        }
        sections.append(SearchSection(kind: .tasks, hits: sorted(taskHits)))

        let shoppingHits: [SearchHit] = shopping.filter { $0.deletedAt == nil && !archivedLists.contains($0.listId) }.compactMap { item in
            let assignee = item.assigneeId.flatMap { names[$0] } ?? ""
            guard let score = score(terms: terms, primary: item.name, secondary: [item.note, item.category, assignee]) else { return nil }
            let who = assignee.isEmpty ? "Любой" : assignee
            return SearchHit(id: "shopping-\(item.id)", kind: .shopping, title: item.name,
                             subtitle: "\(ShoppingFormat.amount(item)) · \(who)\(item.isBought ? " · куплено" : "")",
                             destination: .shoppingItem(item.id), isMuted: item.isBought, score: score + (item.isBought ? 0 : 50))
        }
        sections.append(SearchSection(kind: .shopping, hits: sorted(shoppingHits)))

        if includeDocuments {
            let documentHits: [SearchHit] = documents.filter { $0.deletedAt == nil }.compactMap { doc in
                let owner = doc.ownerId.flatMap { names[$0] } ?? ""
                guard let score = score(terms: terms, primary: doc.title, secondary: [doc.number, doc.fileName, doc.category.title, owner]) else { return nil }
                var parts = [doc.category.title]
                if !owner.isEmpty { parts.append(owner) }
                if let expires = doc.expiresAt {
                    parts.append("до \(expires.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "ru_RU"))))")
                }
                return SearchHit(id: "document-\(doc.id)", kind: .documents, title: doc.title, subtitle: parts.joined(separator: " · "),
                                 destination: .document(doc.id), isMuted: false, score: score)
            }
            sections.append(SearchSection(kind: .documents, hits: sorted(documentHits)))
        }
        return sections.filter { !$0.hits.isEmpty }
    }

    /// Все слова запроса должны найтись: в названии (вес больше) или в дополнительных полях.
    static func score(terms: [String], primary: String, secondary: [String]) -> Int? {
        var total = 0
        for term in terms {
            let inPrimary = SearchMatcher.weight(term: term, in: primary)
            let inSecondary = secondary.map { SearchMatcher.weight(term: term, in: $0) }.max() ?? 0
            guard inPrimary > 0 || inSecondary > 0 else { return nil }
            total += max(inPrimary * 30, inSecondary * 10)
        }
        return total
    }

    private static func sorted(_ hits: [SearchHit]) -> [SearchHit] {
        hits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func taskSubtitle(_ task: TaskOccurrenceRecord, assignee: String, calendar: Calendar, now: Date) -> String {
        let day: String
        if calendar.isDate(task.dueAt, inSameDayAs: now) { day = "сегодня" }
        else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(task.dueAt, inSameDayAs: tomorrow) { day = "завтра" }
        else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(task.dueAt, inSameDayAs: yesterday) { day = "вчера" }
        else { day = RussianDate.dayMonth(task.dueAt, calendar: calendar) }
        var parts = [task.hasTime ? "\(day), \(RussianDate.time(task.dueAt, calendar: calendar))" : day]
        if !assignee.isEmpty { parts.append(assignee) }
        if task.isCompleted { parts.append("выполнено") }
        return parts.joined(separator: " · ")
    }
}

/// Недавние запросы (на этом устройстве).
public enum SearchHistory {
    static let key = "recentSearches"
    static let limit = 6

    public static func load(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public static func remember(_ query: String, defaults: UserDefaults = .standard) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        var list = load(defaults: defaults).filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        defaults.set(Array(list.prefix(limit)), forKey: key)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
