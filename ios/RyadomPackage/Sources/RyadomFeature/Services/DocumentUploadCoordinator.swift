import Foundation
import Observation
import SwiftData

/// Отправляет документы на сервер: создание записи → прямая загрузка в хранилище → подтверждение.
/// Повтор безопасен: создание идемпотентно по `id`, а сервер выдаёт новую ссылку и не создаёт дубликат.
@Observable
@MainActor
public final class DocumentUploadCoordinator {
    public struct Progress: Equatable, Sendable {
        public var sent: Int64
        public var total: Int64
        public var etaSeconds: Int?
        public var fraction: Double { total > 0 ? min(1, Double(sent) / Double(total)) : 0 }
    }

    public enum State: Equatable, Sendable {
        case running(Progress)
        case failed(title: String, detail: String)
        case finished
    }

    public private(set) var states: [UUID: State] = [:]

    private let context: ModelContext
    private let store: DocumentFileStore
    private let api: any DocumentAPI
    private let transfer: any StorageTransferring
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(context: ModelContext, store: DocumentFileStore, api: any DocumentAPI, transfer: any StorageTransferring) {
        self.context = context
        self.store = store
        self.api = api
        self.transfer = transfer
    }

    public func state(for id: UUID) -> State? { states[id] }

    /// Дожидается завершения текущей загрузки (для тестов и фоновых сценариев).
    public func waitForCompletion(_ id: UUID) async {
        await tasks[id]?.value
    }

    public func start(_ id: UUID) {
        guard tasks[id] == nil, let doc = document(id) else { return }
        states[id] = .running(Progress(sent: 0, total: Int64(doc.sizeBytes), etaSeconds: nil))
        doc.uploadState = .uploading
        tasks[id] = Task { [weak self] in
            await self?.run(id)
            self?.tasks[id] = nil
        }
    }

    /// Повторная загрузка после ошибки. Название, категория и доступ уже сохранены.
    public func retry(_ id: UUID) {
        guard tasks[id] == nil else { return }
        states[id] = nil
        start(id)
    }

    /// Отмена: файл не добавится в хранилище. Запись и локальная копия удаляются.
    public func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        states[id] = nil
        guard let doc = document(id) else { return }
        store.remove(doc.localFileName)
        // Сервер мог уже создать запись — удаление в очереди уберёт её (для неизвестной записи оно безвредно).
        context.insert(OutboxOperation(entity: .document, entityId: id, type: .delete, baseVersion: doc.version, payload: Data()))
        context.delete(doc)
        try? context.save()
    }

    /// Возвращает локальную копию файла; если её нет (документ добавил другой участник или копия была
    /// стёрта), скачивает по короткоживущей ссылке прямо из хранилища.
    public func ensureLocalFile(for id: UUID) async throws -> URL {
        guard let doc = document(id) else { throw DocumentTransferError.server("Документ не найден.") }
        if let name = doc.localFileName, store.exists(name) { return store.url(for: name) }
        let kind = DocumentFileKind(mimeType: doc.mimeType) ?? .pdf
        let target = try store.reserve(documentId: id, kind: kind)
        let link = try await api.downloadURL(documentId: id)
        try await transfer.download(from: link, to: target.url)
        guard let data = try? Data(contentsOf: target.url), DocumentFileKind.sniff(data) == kind else {
            store.remove(target.name)
            throw DocumentTransferError.rejected("Файл повреждён. Попробуйте ещё раз.")
        }
        store.protect(target.name)
        doc.localFileName = target.name
        try? context.save()
        return target.url
    }

    // MARK: Внутреннее

    private func run(_ id: UUID) async {
        guard let doc = document(id), let name = doc.localFileName, store.exists(name) else {
            fail(id, .server("Файл не найден на устройстве."))
            return
        }
        let file = store.url(for: name)
        let meta = DocumentUploadMetadata(
            id: id, title: doc.title, fileName: doc.fileName.isEmpty ? "\(doc.title).\(DocumentFileKind(mimeType: doc.mimeType)?.fileExtension ?? "pdf")" : doc.fileName,
            mimeType: doc.mimeType, sizeBytes: doc.sizeBytes, category: doc.category, ownerId: doc.ownerId,
            number: doc.number, expiresAt: doc.expiresAt, access: doc.access, selectedUserIds: doc.sharedWith)
        let started = Date()
        let report: @Sendable (Int64, Int64) -> Void = { [weak self] sent, total in
            Task { @MainActor in self?.report(id, sent: sent, total: total, since: started) }
        }
        do {
            var slot = try await api.createDocument(meta)
            do {
                try await transfer.upload(file: file, to: slot, progress: report)
            } catch DocumentTransferError.slotExpired {
                slot = try await api.newUploadSlot(documentId: id)
                try await transfer.upload(file: file, to: slot, progress: report)
            }
            try await api.confirmUpload(documentId: id)
            finish(id)
        } catch is CancellationError {
            // Отмену обработал cancel(_:).
        } catch let error as DocumentTransferError {
            fail(id, error)
        } catch {
            fail(id, .offline)
        }
    }

    private func report(_ id: UUID, sent: Int64, total: Int64, since start: Date) {
        guard case .running = states[id] else { return }
        let elapsed = Date().timeIntervalSince(start)
        var eta: Int?
        if elapsed > 0.8, sent > 0 {
            let rate = Double(sent) / elapsed
            eta = max(1, Int(((Double(total - sent)) / rate).rounded(.up)))
        }
        states[id] = .running(Progress(sent: sent, total: total, etaSeconds: eta))
    }

    private func finish(_ id: UUID) {
        if let doc = document(id) {
            doc.uploadState = .synced
            doc.syncStatus = .synced
            doc.updatedAt = .now
            try? context.save()
        }
        states[id] = .finished
    }

    private func fail(_ id: UUID, _ error: DocumentTransferError) {
        if let doc = document(id) {
            doc.uploadState = .failed
            try? context.save()
        }
        let message = error.userMessage
        states[id] = .failed(title: message.title, detail: message.detail)
    }

    private func document(_ id: UUID) -> DocumentRecord? {
        (try? context.fetch(FetchDescriptor<DocumentRecord>(predicate: #Predicate { $0.id == id })))?.first
    }
}
