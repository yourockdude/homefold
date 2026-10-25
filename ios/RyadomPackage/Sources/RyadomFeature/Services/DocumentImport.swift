import Foundation
import UIKit
import PDFKit

public enum DocumentFileKind: String, Sendable, CaseIterable {
    case pdf, jpeg, png

    public var mimeType: String {
        switch self {
        case .pdf: "application/pdf"
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        }
    }

    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public var shortTitle: String { self == .jpeg ? "JPG" : rawValue.uppercased() }
    public var isImage: Bool { self != .pdf }

    public init?(mimeType: String) {
        guard let kind = Self.allCases.first(where: { $0.mimeType == mimeType }) else { return nil }
        self = kind
    }

    /// Определяет тип по сигнатуре файла, а не по расширению.
    public static func sniff(_ data: Data) -> DocumentFileKind? {
        let head = [UInt8](data.prefix(8))
        if head.starts(with: [0x25, 0x50, 0x44, 0x46, 0x2D]) { return .pdf }
        if head.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        return nil
    }
}

public enum DocumentImportError: LocalizedError, Equatable {
    case unsupportedType
    case tooLarge
    case empty
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: "Поддерживаются только PDF, JPG и PNG."
        case .tooLarge: "Файл больше 25 МБ. Выберите файл поменьше."
        case .empty: "Файл пустой."
        case .unreadable: "Не удалось прочитать файл."
        }
    }
}

/// Файл, готовый к добавлению: проверенный тип и размер.
public struct ImportedFile: Sendable, Equatable {
    public let data: Data
    public let fileName: String
    public let kind: DocumentFileKind

    public var sizeBytes: Int { data.count }
    public var suggestedTitle: String { (fileName as NSString).deletingPathExtension }
}

public enum DocumentImport {
    /// Лимит одного файла — как на сервере (25 МиБ).
    public static let maxFileBytes = 25 * 1024 * 1024

    public static func validate(data: Data, fileName: String) throws -> ImportedFile {
        guard !data.isEmpty else { throw DocumentImportError.empty }
        guard data.count <= maxFileBytes else { throw DocumentImportError.tooLarge }
        guard let kind = DocumentFileKind.sniff(data) else { throw DocumentImportError.unsupportedType }
        return ImportedFile(data: data, fileName: fileName, kind: kind)
    }

    /// Файл из системного «Файлы». URL защищён security-scoped доступом.
    public static func file(at url: URL) throws -> ImportedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileBytes {
            throw DocumentImportError.tooLarge
        }
        guard let data = try? Data(contentsOf: url) else { throw DocumentImportError.unreadable }
        return try validate(data: data, fileName: url.lastPathComponent)
    }

    /// Фото из «Фото»: JPEG и PNG берём как есть, остальное (HEIC и т. п.) перекодируем в JPEG.
    public static func photo(data: Data, suggestedName: String = "Фото") throws -> ImportedFile {
        if DocumentFileKind.sniff(data) != nil { return try validate(data: data, fileName: suggestedName) }
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw DocumentImportError.unsupportedType
        }
        return try validate(data: jpeg, fileName: (suggestedName as NSString).deletingPathExtension + ".jpg")
    }

    /// Страницы со сканера, собранные в один PDF.
    public static func scan(pages: [UIImage], name: String = "Скан") throws -> ImportedFile {
        guard !pages.isEmpty else { throw DocumentImportError.empty }
        let pdf = PDFDocument()
        for (index, image) in pages.enumerated() {
            guard let page = PDFPage(image: image) else { throw DocumentImportError.unreadable }
            pdf.insert(page, at: index)
        }
        guard let data = pdf.dataRepresentation() else { throw DocumentImportError.unreadable }
        return try validate(data: data, fileName: name + ".pdf")
    }
}
