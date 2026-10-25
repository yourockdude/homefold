import Foundation

/// Расчёт дат выполнений для правила повторения.
public enum RecurrenceEngine {
    /// Окно, на которое материализуются выполнения повторяющегося дела.
    public static let horizonDays = 60

    /// Даты выполнений серии от `start` до `horizon` включительно. Для разового дела — одна дата.
    public static func dates(start: Date, recurrence: Recurrence, until horizon: Date, calendar: Calendar) -> [Date] {
        guard recurrence != .none else { return [start] }
        let component: Calendar.Component
        switch recurrence {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .none: return [start]
        }
        var result: [Date] = []
        var step = 0
        // Каждая дата считается от начала серии, а не от предыдущей: 31 января → 28 февраля → 31 марта.
        while let next = calendar.date(byAdding: component, value: step, to: start), next <= horizon {
            result.append(next)
            step += 1
            if step > 400 { break }
        }
        return result
    }
}

enum RussianDate {
    private static func formatter(_ pattern: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = pattern
        return f
    }

    /// «22 октября»
    static func dayMonth(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("d MMMM", calendar).string(from: date)
    }

    /// «Суббота, 24 октября»
    static func weekdayDayMonth(_ date: Date, calendar: Calendar = .current) -> String {
        let text = formatter("EEEE, d MMMM", calendar).string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("HH:mm", calendar).string(from: date)
    }

    /// Короткое название дня недели: «ПН».
    static func shortWeekday(_ date: Date, calendar: Calendar = .current) -> String {
        formatter("EEEEEE", calendar).string(from: date).uppercased()
    }

    /// «на эту субботу», «на этот четверг» — винительный падеж с согласованным указательным словом.
    static func onThisWeekday(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: "на это воскресенье"
        case 2: "на этот понедельник"
        case 3: "на этот вторник"
        case 4: "на эту среду"
        case 5: "на этот четверг"
        case 6: "на эту пятницу"
        default: "на эту субботу"
        }
    }

    /// «Каждый четверг» и т. п.
    static func everyWeekday(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: "Каждое воскресенье"
        case 2: "Каждый понедельник"
        case 3: "Каждый вторник"
        case 4: "Каждую среду"
        case 5: "Каждый четверг"
        case 6: "Каждую пятницу"
        default: "Каждую субботу"
        }
    }
}

extension Recurrence {
    /// Подпись правила с учётом даты начала («Каждый четверг», «Каждое 22-е число»).
    func title(for date: Date, calendar: Calendar = .current) -> String {
        switch self {
        case .none: "Без повтора"
        case .daily: "Каждый день"
        case .weekly: RussianDate.everyWeekday(date, calendar: calendar)
        case .monthly: "Каждое \(calendar.component(.day, from: date))-е число"
        }
    }
}
