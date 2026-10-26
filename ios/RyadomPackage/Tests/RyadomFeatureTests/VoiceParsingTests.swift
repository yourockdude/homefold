import Testing
import Foundation
@testable import RyadomFeature

@Suite struct VoiceShoppingParserTests {
    private func parse(_ text: String) -> [(String, Double, ShoppingUnit, ShoppingCategory)] {
        VoiceShoppingParser.parse(text).map { ($0.name, $0.quantity, $0.unit, $0.category) }
    }

    private func expect(_ text: String, _ expected: [(String, Double, ShoppingUnit, ShoppingCategory)], sourceLocation: SourceLocation = #_sourceLocation) {
        let actual = parse(text)
        #expect(actual.count == expected.count, "\(text) → \(actual)", sourceLocation: sourceLocation)
        for (a, e) in zip(actual, expected) {
            #expect(a.0 == e.0 && a.1 == e.1 && a.2 == e.2 && a.3 == e.3, "\(text) → \(a) ≠ \(e)", sourceLocation: sourceLocation)
        }
    }

    @Test func listWithCommasAndConjunction() {
        expect("молоко два литра, хлеб, яйца десять штук и яблоки килограмм", [
            ("Молоко", 2, .liter, .dairy), ("Хлеб", 1, .piece, .bakery),
            ("Яйца", 10, .piece, .dairy), ("Яблоки", 1, .kilogram, .produce),
        ])
    }

    @Test func triggerWordsAreDropped() {
        expect("добавь в список покупок сыр пятьсот грамм и полкило помидоров", [
            ("Сыр", 500, .gram, .dairy), ("Помидоров", 0.5, .kilogram, .produce),
        ])
        expect("надо купить пасту и зубную щётку", [("Пасту", 1, .piece, .pantry), ("Зубную щётку", 1, .piece, .household)])
    }

    @Test func fractionsAndDecimals() {
        expect("купить полтора литра кефира", [("Кефира", 1.5, .liter, .dairy)])
        expect("3 яблока, 2,5 кг картошки", [("Яблока", 3, .piece, .produce), ("Картошки", 2.5, .kilogram, .produce)])
        expect("поллитра сливок", [("Сливок", 0.5, .liter, .dairy)])
    }

    @Test func percentsAndDigitsInNamesStayInName() {
        expect("молоко 3,2%", [("Молоко 3,2%", 1, .piece, .dairy)])
        expect("яйца С1 десять штук", [("Яйца С1", 10, .piece, .dairy)])
    }

    @Test func unitWithoutNumberMeansOne() {
        expect("литр молока", [("Молока", 1, .liter, .dairy)])
        expect("пачка масла", [("Масла", 1, .pack, .dairy)])
    }

    @Test func compoundNumbersAndBareCounts() {
        expect("двадцать пять штук яиц", [("Яиц", 25, .piece, .dairy)])
        expect("пять яблок", [("Яблок", 5, .piece, .produce)])
        expect("двести граммов ветчины", [("Ветчины", 200, .gram, .meat)])
    }

    @Test func quantityGivenAsSeparatePart() {
        expect("молоко, два литра", [("Молоко", 2, .liter, .dairy)])
    }

    @Test func unknownItemsGoToOther() {
        expect("скотч", [("Скотч", 1, .piece, .other)])
    }

    @Test func emptyOrOnlyTriggersGiveNothing() {
        #expect(VoiceShoppingParser.parse("").isEmpty)
        #expect(VoiceShoppingParser.parse("добавь в список").isEmpty)
    }
}

@Suite struct VoiceTaskParserTests {
    /// Понедельник, 26 октября 2026, 14:00 (Москва).
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow")!
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        return c
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 14))! }
    private let anna = UUID(), mikhail = UUID(), sonya = UUID()
    private var members: [(id: UUID, name: String)] { [(anna, "Анна"), (mikhail, "Михаил"), (sonya, "Соня")] }

    private func parse(_ text: String) -> ParsedTask {
        VoiceTaskParser.parse(text, now: now, calendar: calendar, members: members, currentUserId: anna)
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func tomorrowAtTime() {
        let t = parse("завтра в 18:30 забрать Соню с танцев")
        #expect(t.title == "Забрать Соню с танцев")
        #expect(t.start == date(10, 27, 18, 30) && t.hasTime)
        #expect(t.assigneeId == nil, "имя в середине названия — не ответственный")
    }

    @Test func assigneeAtTheEnd() {
        let t = parse("забрать Соню с танцев Михаилу")
        #expect(t.title == "Забрать Соню с танцев")
        #expect(t.assigneeId == mikhail)
    }

    @Test func assigneeBeforeTrailingReminderPhrase() {
        let t = parse("завтра в 18:30 забрать Соню с танцев Михаилу напомнить за час")
        #expect(t.assigneeId == mikhail && t.title == "Забрать Соню с танцев")
        #expect(t.reminderMinutes == .some(60))
    }

    @Test func assigneeAfterFor() {
        let t = parse("для Анны завтра в семь тридцать вечера ужин")
        #expect(t.assigneeId == anna && t.title == "Ужин")
        #expect(t.start == date(10, 27, 19, 30))
    }

    @Test func meMeansCurrentUser() {
        let t = parse("мне завтра купить хлеб")
        #expect(t.assigneeId == anna && t.title == "Купить хлеб")
    }

    @Test func weekdayAndMorning() {
        let t = parse("позвонить бабушке в субботу в 10 утра")
        #expect(t.title == "Позвонить бабушке")
        #expect(t.start == date(10, 31, 10, 0) && t.hasTime)
    }

    @Test func dailyRecurrenceTodayEvening() {
        let t = parse("полить растения каждый день в 19:00")
        #expect(t.recurrence == .daily && t.title == "Полить растения")
        #expect(t.start == date(10, 26, 19, 0))
    }

    @Test func weeklyOnWeekdaySkipsToday() {
        let t = parse("каждый понедельник в 8 утра вынести мусор")
        #expect(t.recurrence == .weekly && t.title == "Вынести мусор")
        #expect(t.start == date(11, 2, 8, 0), "сегодня понедельник — следующий через неделю")
    }

    @Test func pluralWeekdayRecurrence() {
        let t = parse("по пятницам убираться")
        #expect(t.recurrence == .weekly && t.title == "Убираться")
        #expect(t.start == date(10, 30, 9, 0) && !t.hasTime)
    }

    @Test func reminderBeforeDeadline() {
        let t = parse("напомни завтра в 9 утра за час купить подарок")
        #expect(t.reminderMinutes == .some(60))
        #expect(t.title == "Купить подарок" && t.start == date(10, 27, 9, 0))
        #expect(parse("завтра в 10 утра встреча за пятнадцать минут").reminderMinutes == .some(10))
        #expect(parse("завтра в 10 утра встреча за день").reminderMinutes == .some(1440))
    }

    @Test func noReminderRequested() {
        let t = parse("без напоминания записать на приём")
        #expect(t.reminderMinutes == .some(nil))
        #expect(t.title == "Записать на приём")
    }

    @Test func dateWithMonthName() {
        let t = parse("оплатить интернет 25 ноября")
        #expect(t.title == "Оплатить интернет")
        #expect(t.start == date(11, 25, 9, 0) && !t.hasTime)
    }

    @Test func pastDateMovesToNextYear() {
        let t = parse("двадцать пятого октября в полдень день рождения")
        #expect(t.start == date(10, 25, 12, 0, year: 2027))
        #expect(t.title == "День рождения")
    }

    @Test func relativeTime() {
        let t = parse("через два часа выключить духовку")
        #expect(t.start == date(10, 26, 16, 0) && t.hasTime)
        #expect(t.title == "Выключить духовку")
        let d = parse("через три дня записаться к врачу")
        #expect(d.start == date(10, 29, 9, 0) && !d.hasTime)
    }

    @Test func bareHourAfternoonHeuristic() {
        let t = parse("в пять вечера встреча с врачом")
        #expect(t.start == date(10, 26, 17, 0) && t.title == "Встреча с врачом")
        #expect(parse("в 5 встреча").start == date(10, 26, 17, 0))
    }

    @Test func halfPastWithOrdinal() {
        let t = parse("в половине седьмого утра зарядка")
        #expect(t.start == date(10, 27, 6, 30), "6:30 уже прошло — завтра")
        #expect(t.title == "Зарядка")
    }

    @Test func timeEarlierThanNowMeansTomorrow() {
        #expect(parse("в 9 утра зарядка").start == date(10, 27, 9, 0))
        #expect(parse("в 18:00 ужин").start == date(10, 26, 18, 0))
    }

    @Test func noDateNoTimeIsTodayWithoutTime() {
        let t = parse("купить подарок")
        #expect(t.title == "Купить подарок" && !t.hasTime && t.recurrence == .none && t.reminderMinutes == nil)
    }

    @Test func emptyTextGivesEmptyTitle() {
        #expect(parse("").title.isEmpty)
        #expect(parse("напомни").title.isEmpty)
    }
}

@Suite struct RussianNumbersTests {
    private func value(_ text: String) -> Double? {
        let words = text.split(separator: " ").map(String.init)
        return RussianNumbers.parse(words, at: 0)?.value
    }

    @Test func wordsAndDigits() {
        #expect(value("два") == 2 && value("двенадцать") == 12 && value("двадцать пять") == 25)
        #expect(value("сто пятьдесят") == 150 && value("триста двадцать один") == 321)
        #expect(value("2") == 2 && value("2,5") == 2.5 && value("0.5") == 0.5)
        #expect(value("полтора") == 1.5)
        #expect(value("молоко") == nil && value("3,2%") == nil && value("18:30") == nil)
    }

    @Test func doesNotJoinSameOrder() {
        // «пять шесть» — два числа, не одиннадцать.
        let words = ["пять", "шесть"]
        #expect(RussianNumbers.parse(words, at: 0)?.length == 1)
    }
}
