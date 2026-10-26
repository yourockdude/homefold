import Foundation
import SwiftData

/// Данные формы документа.
public struct DocumentDraft: Equatable, Sendable {
    public var title = ""
    public var category = DocumentCategory.personal
    public var ownerId: UUID?
    public var number = ""
    public var expiresAt: Date?
    public var access = DocumentAccess.family
    public var selectedUserIds: Set<UUID> = []

    public init() {}

    public init(_ doc: DocumentRecord) {
        title = doc.title
        category = doc.category
        ownerId = doc.ownerId
        number = doc.number
        expiresAt = doc.expiresAt
        access = doc.access
        selectedUserIds = Set(doc.sharedWith)
    }

    public enum Problem: Equatable, Sendable {
        case emptyTitle
        case noRecipients
    }

    public var problem: Problem? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .emptyTitle }
        if access == .selected && selectedUserIds.isEmpty { return .noRecipients }
        return nil
    }
}

public enum DocumentServiceError: Error, Equatable {
    case invalidDraft(DocumentDraft.Problem)
    case limitReached(DocumentLimitReason)
    case notAuthor
}

public enum DocumentLimitReason: Equatable, Sendable {
    case totalSize
}

/// Лимит хранилища документов семьи. Источник истины — сервер; клиент проверяет заранее, чтобы не гонять файл зря.
public enum DocumentLimits {
    public static let totalBytes = 10 * 1024 * 1024 * 1024

    public static func check(currentBytes: Int, adding size: Int) -> DocumentLimitReason? {
        currentBytes + size > totalBytes ? .totalSize : nil
    }
}

/// Метаданные документа в теле операции синхронизации (поля совпадают с API).
struct DocumentMetaPayload: Codable {
    var title: String
    var category: String
    var ownerId: UUID?
    var number: String
    var expiresAt: String?
    var access: String
    var selectedUserIds: [UUID]
}

/// Локальные действия над документами.
@MainActor
public final class DocumentService {
    private let context: ModelContext
    private let familyId: UUID
    private let userId: UUID
    private let store: DocumentFileStore

    public init(context: ModelContext, familyId: UUID, userId: UUID, store: DocumentFileStore = DocumentFileStore()) {
        self.context = context
        self.familyId = familyId
        self.userId = userId
        self.store = store
    }

    // MARK: Лимиты

    public func usage() -> (files: Int, bytes: Int) {
        let docs = liveDocuments()
        return (docs.count, docs.reduce(0) { $0 + $1.sizeBytes })
    }

    public func limitReason(adding size: Int) -> DocumentLimitReason? {
        let u = usage()
        return DocumentLimits.check(currentBytes: u.bytes, adding: size)
    }

    // MARK: Создание и правка

    /// Сохраняет файл на устройстве и создаёт запись со статусом «Ожидает синхронизации».
    /// Работает без сети: отправка на сервер — отдельный шаг (`DocumentUploadCoordinator`).
    @discardableResult
    public func add(_ draft: DocumentDraft, file: ImportedFile) throws -> DocumentRecord {
        if let problem = draft.problem { throw DocumentServiceError.invalidDraft(problem) }
        if let reason = limitReason(adding: file.sizeBytes) { throw DocumentServiceError.limitReached(reason) }
        let id = UUID()
        let name = try store.save(file.data, documentId: id, kind: file.kind)
        let doc = DocumentRecord(
            id: id, familyId: familyId, authorId: userId, ownerId: draft.ownerId, title: clean(draft.title),
            category: draft.category, number: clean(draft.number), expiresAt: draft.expiresAt,
            access: draft.access, sharedWith: draft.access == .selected ? Array(draft.selectedUserIds) : [],
            mimeType: file.kind.mimeType, sizeBytes: file.sizeBytes, localFileName: name, fileName: file.fileName)
        context.insert(doc)
        save()
        return doc
    }

    /// Правка метаданных. Менять документ может только автор.
    @discardableResult
    public func update(_ doc: DocumentRecord, with draft: DocumentDraft) throws -> Bool {
        guard doc.authorId == userId else { throw DocumentServiceError.notAuthor }
        if let problem = draft.problem { throw DocumentServiceError.invalidDraft(problem) }
        doc.title = clean(draft.title)
        doc.category = draft.category
        doc.ownerId = draft.ownerId
        doc.number = clean(draft.number)
        doc.expiresAt = draft.expiresAt
        doc.access = draft.access
        doc.sharedWith = draft.access == .selected ? Array(draft.selectedUserIds) : []
        doc.updatedAt = .now
        doc.syncStatus = .pending
        // Пока документ не загружен, метаданные уйдут вместе с созданием.
        if doc.uploadState == .synced { enqueueMeta(doc) }
        save()
        return true
    }

    /// Удаляет документ у всей семьи и стирает локальный файл.
    public func delete(_ doc: DocumentRecord) throws {
        guard doc.authorId == userId else { throw DocumentServiceError.notAuthor }
        guard doc.deletedAt == nil else { return }
        doc.deletedAt = .now
        doc.updatedAt = .now
        doc.syncStatus = .pending
        store.remove(doc.localFileName)
        doc.localFileName = nil
        enqueue(.delete, doc, EmptyBody())
        save()
    }

    /// Доступ к документу закрыт: стираем локальную копию вместе с записью.
    /// Мгновенно отозвать файл на отключённом устройстве нельзя — вызывается при следующей синхронизации.
    public func revokeAccess(documentId: UUID) {
        let descriptor = FetchDescriptor<DocumentRecord>(predicate: #Predicate { $0.id == documentId })
        guard let doc = (try? context.fetch(descriptor))?.first else { return }
        store.remove(doc.localFileName)
        context.delete(doc)
        save()
    }

    /// Файлы без записей и записи с пропавшим файлом (кроме тех, что ещё надо скачать).
    public func cleanOrphans() {
        let names = Set(((try? context.fetch(FetchDescriptor<DocumentRecord>())) ?? []).compactMap(\.localFileName))
        store.removeOrphans(keeping: names)
    }

    // MARK: Запросы

    public func liveDocuments() -> [DocumentRecord] {
        let fid = familyId
        let descriptor = FetchDescriptor<DocumentRecord>(predicate: #Predicate { $0.familyId == fid && $0.deletedAt == nil })
        return (try? context.fetch(descriptor)) ?? []
    }

    public func fileURL(for doc: DocumentRecord) -> URL? {
        guard let name = doc.localFileName, store.exists(name) else { return nil }
        return store.url(for: name)
    }

    // MARK: Внутреннее

    private struct EmptyBody: Codable {}

    private func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func enqueueMeta(_ doc: DocumentRecord) {
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        enqueue(.upsert, doc, DocumentMetaPayload(
            title: doc.title, category: doc.category.rawValue, ownerId: doc.ownerId, number: doc.number,
            expiresAt: doc.expiresAt.map(day.string(from:)), access: doc.access.rawValue, selectedUserIds: doc.sharedWith))
    }

    private func enqueue<P: Encodable>(_ type: SyncOperationType, _ doc: DocumentRecord, _ payload: P) {
        let encoder = JSONEncoder()
        context.insert(OutboxOperation(entity: .document, entityId: doc.id, type: type, baseVersion: doc.version,
                                       payload: (try? encoder.encode(payload)) ?? Data()))
    }

    private func save() {
        do { try context.save() } catch { assertionFailure("Не удалось сохранить: \(error)") }
    }
}

/// Поиск по документам: название, имя файла, номер, категория и имя владельца; без учёта регистра и «ё».
public enum DocumentSearch {
    public static func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func filter(_ docs: [DocumentRecord], query: String, category: DocumentCategory? = nil,
                              owners: [UUID: String] = [:]) -> [DocumentRecord] {
        let q = normalize(query)
        return docs.filter { doc in
            if let category, doc.category != category { return false }
            guard !q.isEmpty else { return true }
            let haystack = [doc.title, doc.fileName, doc.number, doc.category.title, doc.ownerId.flatMap { owners[$0] } ?? ""]
                .map(normalize)
            return haystack.contains { $0.contains(q) }
        }
    }
}
