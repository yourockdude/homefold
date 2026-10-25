import Foundation
import SwiftData
import UIKit

#if DEBUG
/// Вымышленные документы семьи Смирновых и симулятор сервера для отладки без бэкенда.
/// Реальных документов и персональных данных здесь нет.
enum DemoDocuments {
    static var failsFirstUpload: Bool { ProcessInfo.processInfo.arguments.contains("-RYUploadFail") }
    /// Загрузка замирает на 64% — для проверки экрана прогресса и отмены.
    static var holdsUpload: Bool { ProcessInfo.processInfo.arguments.contains("-RYUploadHold") }
    static var prefillsFile: Bool { ProcessInfo.processInfo.arguments.contains("-RYPrefillFile") }
    static var forcesCameraDenied: Bool { ProcessInfo.processInfo.arguments.contains("-RYCameraDenied") }
    static var seedsEmptyStorage: Bool { ProcessInfo.processInfo.arguments.contains("-RYEmptyDocuments") }

    @MainActor
    static func seed(into context: ModelContext, store: DocumentFileStore, familyId: UUID,
                     anna: UUID, mikhail: UUID, sonya: UUID) {
        store.removeOrphans(keeping: [])
        guard !seedsEmptyStorage else { return }
        let cal = Calendar.current
        func ago(_ days: Int) -> Date { cal.date(byAdding: .day, value: -days, to: .now) ?? .now }
        let expiry = cal.date(from: DateComponents(year: 2027, month: 8, day: 31))

        struct Item {
            var title: String; var category: DocumentCategory; var owner: UUID; var author: UUID
            var kind: DocumentFileKind; var size: Int; var daysAgo: Int; var number: String = ""; var expires: Date? = nil
            var page: [String]
        }
        let items: [Item] = [
            Item(title: "Полис ДМС · Соня", category: .health, owner: sonya, author: anna, kind: .pdf, size: 2_400_000,
                 daysAgo: 5, number: "7428 1053 609", expires: expiry,
                 page: ["МЕДСОЮЗ", "Полис ДМС", "Добровольное медицинское страхование", "Смирнова София Михайловна",
                        "№ 7428 1053 609", "01.09.2026 — 31.08.2027", "Программа «Здоровое детство»"]),
            Item(title: "Страховка квартиры", category: .home, owner: anna, author: anna, kind: .pdf, size: 840_000,
                 daysAgo: 7, number: "КВ-0001-2026", page: ["Страховка квартиры", "Учебный документ", "Вымышленные данные"]),
            Item(title: "Паспорт · Анна", category: .personal, owner: anna, author: anna, kind: .jpeg, size: 1_800_000,
                 daysAgo: 10, page: ["Паспорт", "Учебное изображение", "Вымышленные данные"]),
            Item(title: "Паспорт · Михаил", category: .personal, owner: mikhail, author: mikhail, kind: .jpeg, size: 1_700_000,
                 daysAgo: 20, page: ["Паспорт", "Учебное изображение", "Вымышленные данные"]),
            Item(title: "СНИЛС · Соня", category: .personal, owner: sonya, author: anna, kind: .pdf, size: 310_000,
                 daysAgo: 30, page: ["СНИЛС", "Учебный документ", "Вымышленные данные"]),
            Item(title: "Билеты в Казань", category: .travel, owner: mikhail, author: mikhail, kind: .pdf, size: 520_000,
                 daysAgo: 40, page: ["Билеты в Казань", "Учебный документ", "Вымышленные данные"]),
        ]
        for item in items {
            let id = UUID()
            let data = item.kind == .pdf ? samplePDF(lines: item.page) : sampleJPEG(lines: item.page)
            let name = (try? store.save(data, documentId: id, kind: item.kind))
            let doc = DocumentRecord(id: id, familyId: familyId, authorId: item.author, ownerId: item.owner, title: item.title,
                                     category: item.category, number: item.number, expiresAt: item.expires, access: .family,
                                     mimeType: item.kind.mimeType, sizeBytes: item.size, localFileName: name,
                                     fileName: item.title + "." + item.kind.fileExtension, createdAt: ago(item.daysAgo))
            doc.uploadState = .synced
            doc.syncStatus = .synced
            context.insert(doc)
        }
        try? context.save()
    }

    /// Образец файла для добавления («spravka.pdf»).
    static func sampleFile() -> ImportedFile? {
        try? DocumentImport.validate(data: samplePDF(lines: ["Справка", "Учебный документ", "Вымышленные данные"]),
                                     fileName: "spravka.pdf")
    }

    static func samplePDF(lines: [String]) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 420, height: 594)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { ctx in
            ctx.beginPage()
            UIColor(red: 0.97, green: 0.97, blue: 0.95, alpha: 1).setFill()
            ctx.fill(bounds)
            var y: CGFloat = 60
            for (index, line) in lines.enumerated() {
                let font = UIFont.systemFont(ofSize: index == 1 ? 28 : 15, weight: index <= 1 ? .semibold : .regular)
                (line as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [
                    .font: font, .foregroundColor: UIColor(red: 0.14, green: 0.24, blue: 0.21, alpha: 1)])
                y += index == 1 ? 50 : 30
            }
        }
    }

    static func sampleJPEG(lines: [String]) -> Data {
        let size = CGSize(width: 420, height: 280)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: 0.91, green: 0.94, blue: 0.91, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            var y: CGFloat = 40
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: 30, y: y), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                    .foregroundColor: UIColor(red: 0.14, green: 0.24, blue: 0.21, alpha: 1)])
                y += 36
            }
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}

/// Заменяет сервер в режиме отладки: «создаёт» запись, выдаёт ссылку и подтверждает загрузку.
struct SimulatedDocumentAPI: DocumentAPI {
    func createDocument(_ meta: DocumentUploadMetadata) async throws -> UploadSlot {
        UploadSlot(url: URL(string: "https://storage.invalid/\(meta.id)")!)
    }
    func newUploadSlot(documentId: UUID) async throws -> UploadSlot { UploadSlot(url: URL(string: "https://storage.invalid/\(documentId)")!) }
    func confirmUpload(documentId: UUID) async throws {}
    func downloadURL(documentId: UUID) async throws -> URL { URL(string: "https://storage.invalid/\(documentId)")! }
}

actor SimulatedStorageTransfer: StorageTransferring {
    private var failuresLeft = DemoDocuments.failsFirstUpload ? 1 : 0

    func upload(file: URL, to slot: UploadSlot, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let total: Int64 = 1_200_000
        let steps = 25
        let limit = DemoDocuments.holdsUpload ? 16 : steps   // 16/25 = 64%, как в макете
        for step in 1...steps {
            if step > limit { try await Task.sleep(for: .seconds(600)) }
            try await Task.sleep(for: .milliseconds(120))
            progress(total * Int64(step) / Int64(steps), total)
            if failuresLeft > 0, step == 8 {
                failuresLeft -= 1
                throw DocumentTransferError.offline
            }
        }
    }

    func download(from url: URL, to destination: URL) async throws {}
}
#endif
