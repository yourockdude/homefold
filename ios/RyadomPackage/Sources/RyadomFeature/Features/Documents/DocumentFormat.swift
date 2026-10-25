import Foundation
import PDFKit
import UIKit

enum DocumentFormat {
    /// «2,4 МБ», «840 КБ» — десятичные приставки, как в макете.
    static func size(_ bytes: Int) -> String {
        let value = Double(bytes)
        if value >= 1_000_000 { return "\(decimal(value / 1_000_000)) МБ" }
        if value >= 1_000 { return "\(Int((value / 1_000).rounded())) КБ" }
        return "\(bytes) Б"
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func kind(_ doc: DocumentRecord) -> String {
        DocumentFileKind(mimeType: doc.mimeType)?.shortTitle ?? "Файл"
    }

    /// «PDF · 2,4 МБ · 20 октября»
    static func subtitle(_ doc: DocumentRecord, calendar: Calendar = .current) -> String {
        "\(kind(doc)) · \(size(doc.sizeBytes)) · \(RussianDate.dayMonth(doc.createdAt, calendar: calendar))"
    }

    static func count(_ n: Int, one: String, few: String, many: String) -> String {
        "\(n) \(OverviewView.plural(n, one, few, many))"
    }

    static func files(_ n: Int) -> String { count(n, one: "файл", few: "файла", many: "файлов") }
    static func documents(_ n: Int) -> String { count(n, one: "документ", few: "документа", many: "документов") }

    static func fullDate(_ date: Date, calendar: Calendar = .current) -> String {
        "\(RussianDate.dayMonth(date, calendar: calendar)) \(calendar.component(.year, from: date))"
    }

    static func pageCount(at url: URL) -> Int? {
        PDFDocument(url: url)?.pageCount
    }

    static func eta(_ seconds: Int?) -> String {
        guard let seconds else { return "считаем время…" }
        if seconds < 60 { return "около \(seconds) \(OverviewView.plural(seconds, "секунды", "секунд", "секунд"))" }
        let m = Int((Double(seconds) / 60).rounded(.up))
        return "около \(m) \(OverviewView.plural(m, "минуты", "минут", "минут"))"
    }

    /// «•••• •••• 609»: скрывает все символы, кроме последних трёх; пробелы сохраняются.
    static func masked(_ number: String) -> String {
        let chars = Array(number)
        guard chars.count > 3 else { return String(repeating: "•", count: chars.count) }
        let visibleFrom = chars.count - 3
        return String(chars.enumerated().map { index, ch in ch == " " || index >= visibleFrom ? ch : "•" })
    }
}
