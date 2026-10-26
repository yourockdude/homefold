import Foundation

// MARK: Числа и слова

/// Слова приводятся к виду для сравнения: нижний регистр, «ё» → «е», без знаков по краям.
enum VoiceText {
    static func normalize(_ word: String) -> String {
        word.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces).subtracting(CharacterSet(charactersIn: "%")))
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Слово заканчивает фразу или часть списка (запятая, точка, точка с запятой).
    static func endsClause(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ",;.!?".contains(last)
    }
}

/// Числа, сказанные словами: «два», «двадцать пять», «полтора», «пятьсот».
enum RussianNumbers {
    private static let units: [String: Double] = [
        "ноль": 0, "один": 1, "одна": 1, "одно": 1, "одну": 1, "два": 2, "две": 2, "три": 3, "четыре": 4,
        "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11,
        "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14, "пятнадцать": 15, "шестнадцать": 16,
        "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19,
    ]
    private static let tens: [String: Double] = [
        "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50, "шестьдесят": 60, "семьдесят": 70,
        "восемьдесят": 80, "девяносто": 90,
    ]
    private static let hundreds: [String: Double] = [
        "сто": 100, "двести": 200, "триста": 300, "четыреста": 400, "пятьсот": 500, "шестьсот": 600,
        "семьсот": 700, "восемьсот": 800, "девятьсот": 900,
    ]
    private static let fractions: [String: Double] = ["полтора": 1.5, "полторы": 1.5, "половина": 0.5, "пол": 0.5, "полу": 0.5]

    /// Порядковые числительные в родительном падеже: «двадцать пятого октября».
    static let ordinals: [String: Double] = [
        "первого": 1, "второго": 2, "третьего": 3, "четвертого": 4, "пятого": 5, "шестого": 6, "седьмого": 7,
        "восьмого": 8, "девятого": 9, "десятого": 10, "одиннадцатого": 11, "двенадцатого": 12,
        "тринадцатого": 13, "четырнадцатого": 14, "пятнадцатого": 15, "шестнадцатого": 16,
        "семнадцатого": 17, "восемнадцатого": 18, "девятнадцатого": 19, "двадцатого": 20, "тридцатого": 30,
    ]

    private static func place(_ value: Double) -> Int { value >= 100 ? 3 : (value >= 20 ? 2 : 1) }

    private static func wordValue(_ word: String) -> Double? {
        units[word] ?? tens[word] ?? hundreds[word]
    }

    static func isNumberWord(_ word: String) -> Bool { wordValue(word) != nil || fractions[word] != nil }

    /// Число с позиции `index`: цифры («2», «2,5») или слова («двадцать пять»). Возвращает значение и число слов.
    static func parse(_ words: [String], at index: Int) -> (value: Double, length: Int)? {
        guard index < words.count else { return nil }
        let first = words[index]
        if let digits = Double(first.replacingOccurrences(of: ",", with: ".")), first.first?.isNumber == true,
           !first.contains("%"), !first.contains(":") { return (digits, 1) }
        if let fraction = fractions[first] { return (fraction, 1) }
        var total = 0.0
        var lastPlace = 4
        var length = 0
        var i = index
        while i < words.count, let value = wordValue(words[i]), place(value) < lastPlace || (length == 0) {
            if length > 0 && place(value) >= lastPlace { break }
            total += value
            lastPlace = place(value)
            length += 1
            i += 1
            if value == 0 { break }
        }
        return length > 0 ? (total, length) : nil
    }

    /// Порядковое число для дат: «пятого», «двадцать первого» → 5, 21.
    static func parseOrdinal(_ words: [String], at index: Int) -> (value: Int, length: Int)? {
        guard index < words.count else { return nil }
        if let direct = ordinals[words[index]] { return (Int(direct), 1) }
        if let ten = tens[words[index]], index + 1 < words.count, let unit = ordinals[words[index + 1]], unit < 10 {
            return (Int(ten + unit), 2)
        }
        return nil
    }
}

// MARK: Покупки

public struct ParsedShoppingItem: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public var name: String
    public var quantity: Double
    public var unit: ShoppingUnit
    public var category: ShoppingCategory

    public static func == (lhs: ParsedShoppingItem, rhs: ParsedShoppingItem) -> Bool {
        lhs.name == rhs.name && lhs.quantity == rhs.quantity && lhs.unit == rhs.unit && lhs.category == rhs.category
    }
}

/// Разбор фразы вроде «молоко два литра, хлеб, яйца десять штук и яблоки килограмм» в позиции списка.
public enum VoiceShoppingParser {
    private static let separators: Set<String> = ["и", "еще", "также", "плюс", "потом", "затем", "ну"]
    /// Вводные слова: отбрасываются, где бы ни встретились.
    private static let fillers: Set<String> = [
        "пожалуйста", "еще", "нужно", "надо", "купить", "купи", "добавь", "добавить", "запиши", "мне", "нужны", "нужен", "нужна",
        "положи", "поставь", "внеси",
    ]
    /// Оборот «в список покупок»: отбрасывается только в начале названия, чтобы не портить «сок в пакете».
    private static let leadingOnly: Set<String> = ["в", "список", "списке", "покупок", "покупки"]

    public static func parse(_ text: String) -> [ParsedShoppingItem] {
        var chunks: [[String]] = []
        var current: [String] = []
        func flush() { if !current.isEmpty { chunks.append(current); current = [] } }
        for raw in text.split(whereSeparator: { $0.isWhitespace || $0 == "\n" }).map(String.init) {
            let norm = VoiceText.normalize(raw)
            if separators.contains(norm) { flush(); continue }
            let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: ",;.!?"))
            if !cleaned.isEmpty { current.append(cleaned) }
            if VoiceText.endsClause(raw) { flush() }
        }
        flush()

        var items: [ParsedShoppingItem] = []
        for chunk in chunks {
            let result = parseChunk(chunk)
            if let item = result.item {
                items.append(item)
            } else if let quantity = result.orphanQuantity, var last = items.popLast(), last.quantity == 1 {
                // «молоко, два литра»: количество пришло отдельной частью.
                last.quantity = quantity.value
                last.unit = quantity.unit
                items.append(last)
            }
        }
        return items
    }

    private static func parseChunk(_ words: [String]) -> (item: ParsedShoppingItem?, orphanQuantity: (value: Double, unit: ShoppingUnit)?) {
        let norm = words.map(VoiceText.normalize)
        var used = [Bool](repeating: false, count: words.count)
        var quantity = 1.0
        var unit = ShoppingUnit.piece

        // Слитные формы: «полкило», «пол-литра».
        for (i, w) in norm.enumerated() {
            if let half = halfForm(w) { quantity = half.value; unit = half.unit; used[i] = true; break }
        }
        if !used.contains(true) {
            var i = 0
            search: while i < norm.count {
                if words[i].contains("%") { i += 1; continue }
                if let (value, length) = RussianNumbers.parse(norm, at: i) {
                    let after = i + length
                    if after < norm.count, let u = ShoppingUnitWords.unit(for: norm[after]) {
                        quantity = value; unit = u
                        for j in i...after { used[j] = true }
                        break search
                    }
                    // Число без единицы: «яблоки 3», «пять яблок» — штуки. Но не «3,2» внутри названия.
                    if value > 0 {
                        quantity = value
                        for j in i..<after { used[j] = true }
                        break search
                    }
                }
                // Единица без числа: «литр молока».
                if let u = ShoppingUnitWords.unit(for: norm[i]) {
                    quantity = 1; unit = u; used[i] = true
                    break search
                }
                i += 1
            }
        }

        var nameWords: [String] = []
        for (i, word) in words.enumerated() where !used[i] {
            if fillers.contains(norm[i]) { continue }
            if nameWords.isEmpty && leadingOnly.contains(norm[i]) { continue }
            nameWords.append(word)
        }
        let name = nameWords.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return (nil, used.contains(true) ? (quantity, unit) : nil)
        }
        let capitalized = VoiceText.capitalizedFirst(name)
        return (ParsedShoppingItem(name: capitalized, quantity: quantity, unit: unit, category: ShoppingCategoryGuess.guess(for: name)), nil)
    }

    /// Слитные формы: «полкило», «поллитра», «пол-литра».
    private static func halfForm(_ word: String) -> (value: Double, unit: ShoppingUnit)? {
        switch word {
        case "пол-литра", "полулитра": return (0.5, .liter)
        case "пол-кило": return (0.5, .kilogram)
        default:
            guard word.hasPrefix("пол"), word.count > 4, let unit = ShoppingUnitWords.unit(for: String(word.dropFirst(3))) else { return nil }
            return (0.5, unit)
        }
    }
}

/// Единицы измерения в разговорной речи.
enum ShoppingUnitWords {
    static func unit(for word: String) -> ShoppingUnit? {
        if word == "л" || word.hasPrefix("литр") { return .liter }
        if word == "мл" || word.hasPrefix("миллилитр") { return .milliliter }
        if word == "кг" || word == "кило" || word.hasPrefix("килограмм") { return .kilogram }
        if word == "г" || word == "гр" || word.hasPrefix("грамм") { return .gram }
        if word == "шт" || word.hasPrefix("штук") { return .piece }
        if word == "уп" || word.hasPrefix("пачк") || word.hasPrefix("упаковк") { return .pack }
        return nil
    }
}

/// Отнесение товара к разделу магазина по ключевым словам. Что не узнали — «Остальное».
public enum ShoppingCategoryGuess {
    private static let table: [(ShoppingCategory, [String])] = [
        (.dairy, ["молок", "кефир", "сыр", "творог", "йогурт", "сметан", "масл", "яйц", "яиц", "слив", "ряженк", "простокваш"]),
        (.produce, ["яблок", "банан", "огурц", "помидор", "томат", "картош", "картофел", "морков", "лук", "капуст", "апельсин",
                    "лимон", "груш", "фрукт", "овощ", "зелен", "укроп", "петрушк", "перец", "перц", "чеснок", "виноград", "мандарин",
                    "клубник", "салат", "авокадо", "кабачк", "свекл"]),
        (.meat, ["мяс", "куриц", "курин", "курят", "говяд", "свинин", "фарш", "колбас", "сосиск", "рыб", "лосос", "форел", "креветк",
                 "филе", "индейк", "бекон", "ветчин"]),
        (.bakery, ["хлеб", "батон", "булк", "багет", "лаваш", "круассан", "выпечк", "пирог", "булочк"]),
        (.pantry, ["макарон", "рис", "греч", "сахар", "мук", "соль", "чай", "кофе", "круп", "овсян", "печень", "конфет", "шоколад",
                   "консерв", "соус", "специ", "мед", "орех", "хлопья", "паст", "вермишел"]),
        (.household, ["мыло", "шампун", "порошок", "бумаг", "салфетк", "губк", "пакет", "мешк", "зубн", "гель", "средств", "лампоч",
                      "батарейк", "полотенц", "тряпк", "кондиционер", "таблетк"]),
    ]

    public static func guess(for name: String) -> ShoppingCategory {
        let words = name.split(separator: " ").map { VoiceText.normalize(String($0)) }
        for (category, stems) in table {
            if words.contains(where: { word in stems.contains { word.hasPrefix($0) } }) { return category }
        }
        return .other
    }
}

// MARK: Дела

public struct ParsedTask: Equatable, Sendable {
    public var title: String
    /// Дата и, если назван, час.
    public var start: Date
    public var hasTime: Bool
    public var recurrence: Recurrence
    /// nil — не сказано (остаётся значение по умолчанию); `.some(nil)` — «без напоминания».
    public var reminderMinutes: Int??
    public var assigneeId: UUID?
}

/// Разбор фразы вроде «завтра в 18:30 забрать Соню с танцев, Михаилу, напомнить за час» в дело.
public enum VoiceTaskParser {
    /// Варианты напоминания в форме дела.
    static let reminderOptions = [0, 10, 30, 60, 1440]

    private static let triggers: Set<String> = [
        "напомни", "напомнить", "напоминание", "создай", "создать", "добавь", "добавить", "поставь", "поставить", "запиши",
        "новое", "дело", "задачу", "задача", "нужно", "надо", "пожалуйста", "мне", "еще", "что", "чтобы",
    ]
    private static let weekdays: [(stem: String, number: Int)] = [
        ("понедельник", 2), ("вторник", 3), ("сред", 4), ("четверг", 5), ("пятниц", 6), ("суббот", 7), ("воскресен", 1),
    ]
    private static let months: [String: Int] = [
        "января": 1, "февраля": 2, "марта": 3, "апреля": 4, "мая": 5, "июня": 6, "июля": 7, "августа": 8,
        "сентября": 9, "октября": 10, "ноября": 11, "декабря": 12,
    ]
    private static let genitiveHours: [String: Int] = [
        "первого": 1, "второго": 2, "третьего": 3, "четвертого": 4, "пятого": 5, "шестого": 6, "седьмого": 7,
        "восьмого": 8, "девятого": 9, "десятого": 10, "одиннадцатого": 11, "двенадцатого": 12,
    ]

    private struct Cursor {
        var originals: [String]
        var norm: [String]
        var used: [Bool]
        init(_ text: String) {
            originals = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            norm = originals.map(VoiceText.normalize)
            used = [Bool](repeating: false, count: originals.count)
        }
        mutating func mark(_ range: Range<Int>) { for i in range { used[i] = true } }
        func free(_ i: Int) -> Bool { i >= 0 && i < used.count && !used[i] }
    }

    public static func parse(_ text: String, now: Date, calendar: Calendar,
                             members: [(id: UUID, name: String)], currentUserId: UUID?) -> ParsedTask {
        var cursor = Cursor(text)
        var recurrence = Recurrence.none
        var recurrenceWeekday: Int?
        var reminder: Int??
        var date: Date?
        var time: (hour: Int, minute: Int)?
        var relativeInstant: Date?
        var assignee: UUID?

        parseRecurrence(&cursor, &recurrence, &recurrenceWeekday)
        parseReminder(&cursor, &reminder)
        if let instant = parseRelative(&cursor, now: now, calendar: calendar) {
            if instant.hasTime { relativeInstant = instant.date } else { date = instant.date }
        }
        if date == nil && relativeInstant == nil { date = parseDate(&cursor, now: now, calendar: calendar, recurrenceWeekday: recurrenceWeekday) }
        if relativeInstant == nil { time = parseTime(&cursor) }
        assignee = parseAssignee(&cursor, members: members, currentUserId: currentUserId)

        // Название — всё, что не распознано, без вводных слов.
        var rest: [String] = []
        for i in 0..<cursor.originals.count where !cursor.used[i] {
            if triggers.contains(cursor.norm[i]) && rest.isEmpty { continue }
            rest.append(cursor.originals[i].trimmingCharacters(in: CharacterSet(charactersIn: ",;.!?")))
        }
        while let last = rest.last, ["в", "на", "к", "для", "по", "и"].contains(VoiceText.normalize(last)) { rest.removeLast() }
        while let first = rest.first, ["в", "на", "к", "для", "и", "что", "чтобы"].contains(VoiceText.normalize(first)) { rest.removeFirst() }
        let title = VoiceText.capitalizedFirst(rest.filter { !$0.isEmpty }.joined(separator: " "))

        // Итоговый момент.
        let start: Date
        let hasTime: Bool
        if let relativeInstant {
            start = relativeInstant; hasTime = true
        } else if let date, let time {
            start = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date) ?? date; hasTime = true
        } else if let time {
            let today = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now) ?? now
            start = today > now ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today); hasTime = true
        } else if let date {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date; hasTime = false
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now; hasTime = false
        }
        return ParsedTask(title: title, start: start, hasTime: hasTime, recurrence: recurrence, reminderMinutes: reminder, assigneeId: assignee)
    }

    // MARK: Повтор

    private static func parseRecurrence(_ c: inout Cursor, _ recurrence: inout Recurrence, _ weekday: inout Int?) {
        for i in 0..<c.norm.count where c.free(i) {
            let w = c.norm[i]
            switch w {
            case "ежедневно": recurrence = .daily; c.mark(i..<i + 1); return
            case "еженедельно": recurrence = .weekly; c.mark(i..<i + 1); return
            case "ежемесячно": recurrence = .monthly; c.mark(i..<i + 1); return
            case "каждый", "каждую", "каждое", "каждые":
                guard c.free(i + 1) else { continue }
                let next = c.norm[i + 1]
                if next == "день" { recurrence = .daily; c.mark(i..<i + 2); return }
                if next == "неделю" { recurrence = .weekly; c.mark(i..<i + 2); return }
                if next == "месяц" { recurrence = .monthly; c.mark(i..<i + 2); return }
                if let day = weekdays.first(where: { next.hasPrefix($0.stem) }) {
                    recurrence = .weekly; weekday = day.number; c.mark(i..<i + 2); return
                }
                if next == "утро" || next == "вечер" { recurrence = .daily; c.mark(i..<i + 2); return }
            case "по":
                guard c.free(i + 1) else { continue }
                let next = c.norm[i + 1]
                if let day = weekdays.first(where: { next.hasPrefix($0.stem) && next.hasSuffix("ам") }) {
                    recurrence = .weekly; weekday = day.number; c.mark(i..<i + 2); return
                }
            default: break
            }
        }
    }

    // MARK: Напоминание

    private static func parseReminder(_ c: inout Cursor, _ reminder: inout Int??) {
        for i in 0..<c.norm.count where c.free(i) {
            let w = c.norm[i]
            if w == "без", c.free(i + 1), c.norm[i + 1].hasPrefix("напоминан") { reminder = .some(nil); c.mark(i..<i + 2); return }
            if w == "не", c.free(i + 1), c.norm[i + 1].hasPrefix("напомина") { reminder = .some(nil); c.mark(i..<i + 2); return }
            guard w == "за", c.free(i + 1) else { continue }
            let next = c.norm[i + 1]
            if next == "полчаса" { reminder = .some(snap(30)); c.mark(i..<i + 2); extendReminderTail(&c, from: i + 2); return }
            if next == "час" { reminder = .some(snap(60)); c.mark(i..<i + 2); extendReminderTail(&c, from: i + 2); return }
            if next == "день" || next == "сутки" { reminder = .some(snap(1440)); c.mark(i..<i + 2); extendReminderTail(&c, from: i + 2); return }
            if let (value, length) = RussianNumbers.parse(c.norm, at: i + 1), c.free(i + 1 + length) {
                let unit = c.norm[i + 1 + length]
                var minutes: Double?
                if unit.hasPrefix("минут") || unit == "мин" { minutes = value }
                else if unit.hasPrefix("час") || unit == "ч" { minutes = value * 60 }
                else if unit.hasPrefix("дн") || unit.hasPrefix("сут") { minutes = value * 1440 }
                if let minutes {
                    reminder = .some(snap(Int(minutes))); c.mark(i..<i + 2 + length); extendReminderTail(&c, from: i + 2 + length)
                    return
                }
            }
        }
    }

    /// Слово «напомнить/напомни» рядом с «за час» — часть оборота, в название не попадает.
    private static func extendReminderTail(_ c: inout Cursor, from index: Int) {
        if c.free(index), c.norm[index].hasPrefix("напомн") { c.used[index] = true }
        var j = index - 1
        while j >= 0, c.used[j] { j -= 1 }
        if j >= 0, c.norm[j].hasPrefix("напомн") { c.used[j] = true }
    }

    private static func snap(_ minutes: Int) -> Int {
        reminderOptions.min { abs($0 - minutes) < abs($1 - minutes) } ?? 30
    }

    // MARK: Относительное время

    /// «Через два часа», «через 15 минут», «через три дня», «через неделю».
    private static func parseRelative(_ c: inout Cursor, now: Date, calendar: Calendar) -> (date: Date, hasTime: Bool)? {
        for i in 0..<c.norm.count where c.free(i) && c.norm[i] == "через" {
            var value = 1.0
            var length = 0
            if let number = RussianNumbers.parse(c.norm, at: i + 1) { value = number.value; length = number.length }
            let unitIndex = i + 1 + length
            guard c.free(unitIndex) else { continue }
            let unit = c.norm[unitIndex]
            func finish(_ component: Calendar.Component, _ amount: Int, hasTime: Bool) -> (Date, Bool)? {
                guard let result = calendar.date(byAdding: component, value: amount, to: now) else { return nil }
                c.mark(i..<unitIndex + 1)
                return (result, hasTime)
            }
            if unit.hasPrefix("минут") || unit == "мин" { return finish(.minute, Int(value), hasTime: true) }
            if unit.hasPrefix("час") { return finish(.hour, Int(value), hasTime: true) }
            if unit == "полчаса" { return finish(.minute, 30, hasTime: true) }
            if unit.hasPrefix("дн") || unit == "день" { return finish(.day, Int(value), hasTime: false) }
            if unit.hasPrefix("недел") { return finish(.day, Int(value) * 7, hasTime: false) }
            if unit.hasPrefix("месяц") { return finish(.month, Int(value), hasTime: false) }
        }
        return nil
    }

    // MARK: Дата

    private static func parseDate(_ c: inout Cursor, now: Date, calendar: Calendar, recurrenceWeekday: Int?) -> Date? {
        let today = calendar.startOfDay(for: now)
        func add(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }
        for i in 0..<c.norm.count where c.free(i) {
            let w = c.norm[i]
            if w == "сегодня" { c.mark(i..<i + 1); return today }
            if w == "завтра" { c.mark(i..<i + 1); return add(1) }
            if w == "послезавтра" { c.mark(i..<i + 1); return add(2) }
            // «25 октября», «двадцать пятого октября»
            if let (day, length) = dayNumber(c, at: i), c.free(i + length), let month = months[c.norm[i + length]] {
                c.mark(i..<i + length + 1)
                var year = calendar.component(.year, from: now)
                var comps = DateComponents(year: year, month: month, day: day)
                if let candidate = calendar.date(from: comps), candidate < today { year += 1; comps.year = year }
                return calendar.date(from: comps)
            }
            // «в понедельник», «во вторник»
            if let day = weekdays.first(where: { w.hasPrefix($0.stem) && !w.hasSuffix("ам") && !w.hasSuffix("ям") }) {
                let current = calendar.component(.weekday, from: now)
                var ahead = (day.number - current + 7) % 7
                if ahead == 0 { ahead = 7 }
                var start = i
                if i > 0, c.free(i - 1), ["в", "во", "на"].contains(c.norm[i - 1]) { start = i - 1 }
                c.mark(start..<i + 1)
                return add(ahead)
            }
        }
        // «каждый понедельник» уже дал день недели.
        if let target = recurrenceWeekday {
            let current = calendar.component(.weekday, from: now)
            var ahead = (target - current + 7) % 7
            if ahead == 0 { ahead = 7 }
            return add(ahead)
        }
        return nil
    }

    private static func dayNumber(_ c: Cursor, at i: Int) -> (Int, Int)? {
        if let ordinal = RussianNumbers.parseOrdinal(c.norm, at: i), (1...31).contains(ordinal.value) { return (ordinal.value, ordinal.length) }
        if let digits = Int(c.norm[i]), (1...31).contains(digits) { return (digits, 1) }
        return nil
    }

    // MARK: Время

    private static func parseTime(_ c: inout Cursor) -> (hour: Int, minute: Int)? {
        for i in 0..<c.norm.count where c.free(i) {
            let w = c.norm[i]
            let hasPreposition = i > 0 && c.free(i - 1) && ["в", "к", "на"].contains(c.norm[i - 1])
            let start = hasPreposition ? i - 1 : i
            if w == "полдень" && hasPreposition { c.mark(start..<i + 1); return (12, 0) }
            if w == "полночь" && hasPreposition { c.mark(start..<i + 1); return (0, 0) }
            // «в половине седьмого»
            if w.hasPrefix("половин"), hasPreposition, c.free(i + 1), let hour = genitiveHours[c.norm[i + 1]] {
                c.mark(start..<i + 2)
                return (adjusted(hour - 1, period: period(c, at: i + 2, &c)), 30)
            }
            guard hasPreposition else {
                // «18:30» без предлога тоже время.
                if let hm = clock(w) { c.mark(i..<i + 1); return (adjusted(hm.hour, period: period(c, at: i + 1, &c), explicit: true), hm.minute) }
                continue
            }
            // «в 18:30»
            if let hm = clock(w) {
                c.mark(start..<i + 1)
                return (adjusted(hm.hour, period: period(c, at: i + 1, &c), explicit: true), hm.minute)
            }
            // «в 7», «в семь тридцать», «в 6 часов вечера»
            guard let (hour, length) = RussianNumbers.parse(c.norm, at: i), hour <= 24 else { continue }
            var end = i + length
            if c.free(end), c.norm[end].hasPrefix("час") { end += 1 }
            var minute = 0
            if c.free(end), let (m, mLength) = RussianNumbers.parse(c.norm, at: end), m < 60, !(c.norm[end].hasPrefix("час")) {
                // «в семь тридцать»: следующее число — минуты. «В 7 утра» сюда не попадает: «утра» не число.
                minute = Int(m); end += mLength
            }
            c.mark(start..<end)
            let p = period(c, at: end, &c)
            return (adjusted(Int(hour), period: p), minute)
        }
        return nil
    }

    private enum DayPeriod { case morning, day, evening, night, none }

    /// Слово «утра/дня/вечера/ночи» после времени; помечает его использованным.
    private static func period(_ c: Cursor, at index: Int, _ target: inout Cursor) -> DayPeriod {
        guard index < c.norm.count, c.free(index) else { return .none }
        let p: DayPeriod
        switch c.norm[index] {
        case "утра": p = .morning
        case "дня": p = .day
        case "вечера": p = .evening
        case "ночи": p = .night
        default: return .none
        }
        target.used[index] = true
        return p
    }

    private static func adjusted(_ hour: Int, period: DayPeriod, explicit: Bool = false) -> Int {
        switch period {
        case .morning: return hour == 12 ? 0 : hour
        case .day: return hour < 12 ? (hour == 0 ? 12 : hour + 12) : hour
        case .evening: return hour < 12 ? hour + 12 : hour
        case .night: return hour == 12 ? 0 : hour
        case .none:
            // Без уточнения «в пять» чаще всего значит 17:00; «в 18:30» — как есть.
            if !explicit, (1...6).contains(hour) { return hour + 12 }
            return min(max(hour, 0), 23)
        }
    }

    private static func clock(_ word: String) -> (hour: Int, minute: Int)? {
        let parts = word.split(whereSeparator: { $0 == ":" || $0 == "." })
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    // MARK: Ответственный

    private static func parseAssignee(_ c: inout Cursor, members: [(id: UUID, name: String)], currentUserId: UUID?) -> UUID? {
        for i in 0..<c.norm.count where c.free(i) {
            let w = c.norm[i]
            if w == "мне" || w == "себе" || w == "я" {
                guard let currentUserId else { continue }
                c.mark(i..<i + 1); return currentUserId
            }
            for member in members where nameMatches(word: w, name: member.name) {
                var start = i
                if i > 0, c.free(i - 1), ["для", "на"].contains(c.norm[i - 1]) { start = i - 1 }
                // «Забрать Соню с танцев»: имя в середине фразы — часть названия дела, назначаем только по явному «для» или в конце/начале.
                let explicit = start != i
                // Края считаем по ещё не разобранным словам: «… Михаилу напомнить за час» — имя в конце названия.
                let freeBefore = (0..<i).contains { c.free($0) }
                let freeAfter = ((i + 1)..<c.norm.count).contains { c.free($0) }
                let atEdge = !freeBefore || !freeAfter || VoiceText.endsClause(c.originals[i]) || (i > 0 && VoiceText.endsClause(c.originals[i - 1]))
                guard explicit || atEdge else { continue }
                c.mark(start..<i + 1)
                return member.id
            }
        }
        return nil
    }

    /// «Михаилу», «Михаила», «Соню», «Сони», «Анне» → по основе имени.
    static func nameMatches(word: String, name: String) -> Bool {
        let n = VoiceText.normalize(name)
        guard !n.isEmpty else { return false }
        if word == n { return true }
        let stem = n.count >= 4 ? String(n.dropLast()) : n
        return word.hasPrefix(stem) && word.count <= n.count + 2 && word.count >= stem.count
    }
}
