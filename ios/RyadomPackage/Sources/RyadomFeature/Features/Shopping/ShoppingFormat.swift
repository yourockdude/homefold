import Foundation

enum ShoppingFormat {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = false
        return f
    }()

    static func quantity(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func parseQuantity(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(normalized)
    }

    static func amount(_ item: ShoppingItemRecord) -> String {
        "\(quantity(item.quantity)) \(item.unit)"
    }

    static func subtitle(_ item: ShoppingItemRecord) -> String {
        item.note.isEmpty ? amount(item) : "\(amount(item)) · \(item.note)"
    }
}

/// Мост для тестов (view-типы internal).
public enum ShoppingFormatBridge {
    public static func goods(_ n: Int) -> String { ShoppingView.goods(n) }
}
