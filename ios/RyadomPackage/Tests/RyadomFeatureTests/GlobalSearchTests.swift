import Testing
import Foundation
import SwiftData
@testable import RyadomFeature

@MainActor
struct GlobalSearchTests {
    let context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
    let family = UUID()
    let anna = UUID()

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }

    /// Поиск по всем данным базы.
    private func search(_ query: String, documents: Bool = true) -> [SearchSection] {
        GlobalSearch.run(query: query, tasks: fetch(TaskOccurrenceRecord.self), checklist: fetch(ChecklistItemRecord.self),
                         shopping: fetch(ShoppingItemRecord.self), lists: fetch(ShoppingListRecord.self),
                         documents: fetch(DocumentRecord.self), members: fetch(MemberRecord.self), includeDocuments: documents)
    }

    private func titles(_ sections: [SearchSection], _ kind: SearchKind) -> [String] {
        sections.first { $0.kind == kind }?.hits.map(\.title) ?? []
    }

    /// Демо-семья: дела, покупки и документы.
    private func seedDemo() { DemoData.seed(into: context) }

    private func list() -> ShoppingListRecord {
        let list = ShoppingListRecord(familyId: family, authorId: anna)
        context.insert(list)
        return list
    }

    @Test func findsAcrossAllSections() {
        seedDemo()
        let sections = search("соня")
        #expect(titles(sections, .tasks).contains("Забрать Соню с танцев"))
        #expect(!titles(sections, .documents).isEmpty, "документы с владельцем Соня")
        #expect(titles(sections, .documents).contains("Полис ДМС · Соня"))
    }

    @Test func ignoresCaseAndYo() {
        seedDemo()
        #expect(titles(search("СЧЕТЧИК"), .tasks) == ["Сверить показания счётчиков"])
        #expect(titles(search("счётчик"), .tasks) == ["Сверить показания счётчиков"])
        #expect(titles(search("ПОЛИС"), .documents).contains("Полис ДМС · Соня"))
    }

    @Test func allWordsMustMatch() {
        seedDemo()
        #expect(titles(search("паспорт анна"), .documents) == ["Паспорт · Анна"])
        #expect(titles(search("паспорт дерево"), .documents).isEmpty)
    }

    @Test func matchesRussianWordForms() {
        let list = list()
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Молока 1 л"))
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Сок яблочный"))
        // Основа слова: «молоко» находит «Молока», «яблоки» — «яблочный» нет (разные основы).
        #expect(titles(search("молоко"), .shopping) == ["Молока 1 л"])
        #expect(titles(search("яблоки"), .shopping).isEmpty)
    }

    @Test func stemMatchingNeedsWordStartAndLongWords() {
        let list = list()
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Лимонад"))
        // «имона» находится внутри слова, а основа «лимо» от слова «лимоны»: начало слова — найдётся.
        #expect(titles(search("лимоны"), .shopping) == ["Лимонад"])
        // Короткое слово («сыр») основу не использует: «сы» не должно находить «сыпучие».
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Сыпучие"))
        #expect(titles(search("сыр"), .shopping).isEmpty)
    }

    @Test func declinedNameFindsItsOwner() {
        seedDemo()
        // «Соню» в названии дела находится по «соня».
        #expect(titles(search("соня"), .tasks).contains("Забрать Соню с танцев"))
    }

    @Test func noMatchesGivesNoSections() {
        seedDemo()
        #expect(search("qwerty").isEmpty)
        #expect(search("   ").isEmpty)
    }

    @Test func documentsAreHiddenWhenLocked() {
        seedDemo()
        #expect(!search("полис", documents: true).isEmpty)
        #expect(search("полис", documents: false).filter { $0.kind == .documents }.isEmpty)
    }

    @Test func searchesNotesAndChecklistAndPlace() {
        let series = UUID()
        let task = TaskOccurrenceRecord(familyId: family, seriesId: series, authorId: anna, title: "Танцы", assigneeId: nil,
                                        place: "Студия «Ритм»", note: "взять форму", dueAt: .now, hasTime: false)
        context.insert(task)
        context.insert(ChecklistItemRecord(familyId: family, occurrenceId: task.id, title: "Бутылка воды", position: 0))
        #expect(titles(search("ритм"), .tasks) == ["Танцы"])
        #expect(titles(search("форму"), .tasks) == ["Танцы"])
        #expect(titles(search("бутылка"), .tasks) == ["Танцы"])
    }

    @Test func titleMatchesRankAboveNoteMatches() {
        let list = list()
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Хлеб", note: "для молока"))
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Молоко"))
        #expect(titles(search("молок"), .shopping) == ["Молоко", "Хлеб"])
    }

    @Test func wordStartRanksAboveInsideWord() {
        let list = list()
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Кукуруза"))
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Рука"))
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Какао"))
        #expect(titles(search("ка"), .shopping).first == "Какао")
    }

    @Test func boughtAndCompletedGoBelowOpenOnes() throws {
        let list = list()
        let bought = ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Яблоки красные")
        bought.isBought = true
        context.insert(bought)
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Яблоки зелёные"))
        #expect(titles(search("яблоки"), .shopping) == ["Яблоки зелёные", "Яблоки красные"])
        let hit = try #require(search("яблоки").first?.hits.last)
        #expect(hit.isMuted && hit.subtitle.contains("куплено"))
    }

    @Test func archivedListsAndDeletedRecordsAreSkipped() {
        let archived = ShoppingListRecord(familyId: family, authorId: anna, title: "Старый", isArchived: true)
        context.insert(archived)
        context.insert(ShoppingItemRecord(familyId: family, listId: archived.id, authorId: anna, name: "Сыр из истории"))
        let active = list()
        let gone = ShoppingItemRecord(familyId: family, listId: active.id, authorId: anna, name: "Сыр удалённый")
        gone.deletedAt = .now
        context.insert(gone)
        context.insert(ShoppingItemRecord(familyId: family, listId: active.id, authorId: anna, name: "Сыр на неделю"))
        #expect(titles(search("сыр"), .shopping) == ["Сыр на неделю"])
    }

    @Test func assigneeNameFindsTheirItems() {
        context.insert(MemberRecord(id: anna, familyId: family, displayName: "Анна", role: "admin", toneIndex: 0))
        let list = list()
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Молоко", assigneeId: anna))
        context.insert(ShoppingItemRecord(familyId: family, listId: list.id, authorId: anna, name: "Хлеб"))
        #expect(titles(search("анна"), .shopping) == ["Молоко"])
    }

    @Test func destinationsPointToTheRecords() throws {
        seedDemo()
        // У повторяющегося дела много выполнений: результат ведёт ровно на одно из них.
        let ids = Set(fetch(TaskOccurrenceRecord.self).filter { $0.title == "Полить растения" }.map(\.id))
        let hit = try #require(search("полить").first?.hits.first)
        guard case .task(let id) = hit.destination else { Issue.record("ожидалось дело"); return }
        #expect(ids.contains(id) && hit.kind == .tasks)
    }
}

@Suite struct SearchHistoryTests {
    private func defaults() throws -> (UserDefaults, () -> Void) {
        let name = "search-history-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: name))
        return (d, { d.removePersistentDomain(forName: name) })
    }

    @Test func remembersNewestFirstWithoutDuplicates() throws {
        let (d, cleanup) = try defaults(); defer { cleanup() }
        SearchHistory.remember("молоко", defaults: d)
        SearchHistory.remember("полис", defaults: d)
        SearchHistory.remember("МОЛОКО", defaults: d)
        #expect(SearchHistory.load(defaults: d) == ["МОЛОКО", "полис"])
    }

    @Test func ignoresVeryShortAndKeepsLimit() throws {
        let (d, cleanup) = try defaults(); defer { cleanup() }
        SearchHistory.remember("а", defaults: d)
        #expect(SearchHistory.load(defaults: d).isEmpty)
        for i in 0..<10 { SearchHistory.remember("запрос \(i)", defaults: d) }
        #expect(SearchHistory.load(defaults: d).count == SearchHistory.limit)
        SearchHistory.clear(defaults: d)
        #expect(SearchHistory.load(defaults: d).isEmpty)
    }
}
