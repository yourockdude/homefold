import Foundation

enum RussianNames {
    /// Эвристика дательного падежа для имён участников: Соня → Соне, Михаил → Михаилу, Мария → Марии.
    /// Для нетипичных имён возможна ошибка; точное склонение потребовало бы словаря.
    static func dative(_ name: String) -> String {
        guard let last = name.last else { return name }
        let stem = String(name.dropLast())
        if name.hasSuffix("ия") { return stem + "и" }
        switch last {
        case "а", "я": return stem + "е"
        case "й", "ь": return stem + "ю"
        case "е", "о", "и", "у", "ы", "э", "ю": return name
        default: return name + "у"
        }
    }
}
