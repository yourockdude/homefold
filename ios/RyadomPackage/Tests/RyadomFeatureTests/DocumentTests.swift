import Testing
import Foundation
import SwiftData
import UIKit
@testable import RyadomFeature

private let pdfBytes = Data("%PDF-1.4\n%test\n".utf8) + Data(repeating: 0x20, count: 64)
private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 0, count: 32)
private let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0, count: 32)

// MARK: Импорт

struct DocumentImportTests {
    @Test("Тип определяется по сигнатуре, а не по расширению")
    func sniff() {
        #expect(DocumentFileKind.sniff(pdfBytes) == .pdf)
        #expect(DocumentFileKind.sniff(jpegBytes) == .jpeg)
        #expect(DocumentFileKind.sniff(pngBytes) == .png)
        #expect(DocumentFileKind.sniff(Data("hello world".utf8)) == nil)
    }

    @Test("Файл с чужим содержимым отклоняется даже с расширением .pdf")
    func rejectsDisguisedFile() {
        #expect(throws: DocumentImportError.unsupportedType) {
            try DocumentImport.validate(data: Data("MZ executable".utf8), fileName: "virus.pdf")
        }
    }

    @Test("Пустой и слишком большой файлы отклоняются")
    func sizeLimits() {
        #expect(throws: DocumentImportError.empty) { try DocumentImport.validate(data: Data(), fileName: "a.pdf") }
        let big = pdfBytes + Data(repeating: 0, count: DocumentImport.maxFileBytes)
        #expect(throws: DocumentImportError.tooLarge) { try DocumentImport.validate(data: big, fileName: "big.pdf") }
    }

    @Test("Подходящий файл принимается, название берётся из имени без расширения")
    func accepts() throws {
        let file = try DocumentImport.validate(data: pdfBytes, fileName: "spravka.pdf")
        #expect(file.kind == .pdf)
        #expect(file.suggestedTitle == "spravka")
        #expect(file.sizeBytes == pdfBytes.count)
    }

    @Test("Фото в формате, отличном от JPEG и PNG, перекодируется в JPEG")
    func photoConversion() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let tiff = try #require(image.pngData().flatMap { UIImage(data: $0)?.jpegData(compressionQuality: 1) })
        #expect(try DocumentImport.photo(data: tiff).kind == .jpeg)
        #expect(throws: DocumentImportError.unsupportedType) { try DocumentImport.photo(data: Data("not an image".utf8)) }
    }

    @Test("Страницы скана собираются в PDF")
    func scanToPDF() throws {
        let page = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 140)).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 140))
        }
        let file = try DocumentImport.scan(pages: [page, page])
        #expect(file.kind == .pdf)
        #expect(file.fileName == "Скан.pdf")
        #expect(throws: DocumentImportError.empty) { try DocumentImport.scan(pages: []) }
    }
}

// MARK: Сервис

@MainActor
struct DocumentServiceTests {
    let context: ModelContext
    let store: DocumentFileStore
    let service: DocumentService
    let family = UUID()
    let user = UUID()
    let other = UUID()

    init(isPremium: Bool = false) {
        context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
        store = DocumentFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("docs-\(UUID().uuidString)"))
        service = DocumentService(context: context, familyId: family, userId: user, store: store, isPremium: isPremium)
    }

    private func draft(_ title: String = "Полис ДМС · Соня") -> DocumentDraft {
        var d = DocumentDraft()
        d.title = title
        d.category = .health
        d.ownerId = other
        return d
    }

    private func file(_ size: Int = 0) throws -> ImportedFile {
        try DocumentImport.validate(data: pdfBytes + Data(repeating: 0x20, count: size), fileName: "polis.pdf")
    }

    private func ops() -> [OutboxOperation] { (try? context.fetch(FetchDescriptor<OutboxOperation>())) ?? [] }

    @Test("Добавление работает без сети: файл на устройстве, статус «Ожидает синхронизации»")
    func addOffline() throws {
        let doc = try service.add(draft(), file: file())
        #expect(doc.uploadState == .pendingUpload)
        #expect(doc.syncStatus == .pending)
        #expect(store.exists(doc.localFileName))
        #expect(doc.mimeType == "application/pdf")
        #expect(doc.authorId == user)
        #expect(doc.ownerId == other)
    }

    @Test("Без названия документ не создаётся, для «выбранных» нужен хотя бы один участник")
    func validation() throws {
        #expect(throws: DocumentServiceError.invalidDraft(.emptyTitle)) { try service.add(draft("  "), file: file()) }
        var d = draft()
        d.access = .selected
        #expect(throws: DocumentServiceError.invalidDraft(.noRecipients)) { try service.add(d, file: file()) }
        d.selectedUserIds = [other]
        let doc = try service.add(d, file: file())
        #expect(doc.sharedWith == [other])
    }

    @Test("Бесплатный тариф: не больше 10 файлов")
    func freeFileLimit() throws {
        for i in 0..<10 { _ = try service.add(draft("Файл \(i)"), file: file()) }
        #expect(throws: DocumentServiceError.limitReached(.fileCount)) { try service.add(draft("Одиннадцатый"), file: file()) }
    }

    @Test("Бесплатный тариф: суммарно не больше 100 МБ, Плюс — больше")
    func freeSizeLimit() {
        #expect(DocumentLimits.check(isPremium: false, currentFiles: 3, currentBytes: 99 * 1024 * 1024, adding: 2 * 1024 * 1024) == .totalSize)
        #expect(DocumentLimits.check(isPremium: false, currentFiles: 3, currentBytes: 10, adding: 10) == nil)
        #expect(DocumentLimits.check(isPremium: true, currentFiles: 50, currentBytes: 5 * 1024 * 1024 * 1024, adding: 1024) == nil)
        #expect(DocumentLimits.check(isPremium: true, currentFiles: 50, currentBytes: DocumentLimits.plusBytes, adding: 1) == .totalSize)
    }

    @Test("Редактировать документ может только автор")
    func onlyAuthorEdits() throws {
        let doc = try service.add(draft(), file: file())
        var changed = draft("Новое название")
        #expect(try service.update(doc, with: changed))
        #expect(doc.title == "Новое название")

        let stranger = DocumentService(context: context, familyId: family, userId: other, store: store)
        changed.title = "Чужая правка"
        #expect(throws: DocumentServiceError.notAuthor) { try stranger.update(doc, with: changed) }
        #expect(throws: DocumentServiceError.notAuthor) { try stranger.delete(doc) }
        #expect(doc.title == "Новое название")
    }

    @Test("Метаданные уходят в очередь только у загруженного документа")
    func metadataQueue() throws {
        let doc = try service.add(draft(), file: file())
        try service.update(doc, with: draft("До загрузки"))
        #expect(ops().isEmpty, "до загрузки метаданные уйдут вместе с созданием")
        doc.uploadState = .synced
        try service.update(doc, with: draft("После загрузки"))
        #expect(ops().count == 1)
        #expect(ops().first?.entity == .document)
    }

    @Test("Удаление стирает локальный файл и ставит операцию в очередь")
    func deleteRemovesFile() throws {
        let doc = try service.add(draft(), file: file())
        let name = try #require(doc.localFileName)
        try service.delete(doc)
        #expect(doc.deletedAt != nil)
        #expect(!store.exists(name))
        #expect(ops().contains { $0.type == .delete && $0.entityId == doc.id })
        #expect(service.liveDocuments().isEmpty)
    }

    @Test("Отзыв доступа стирает файл и запись, операций не создаёт")
    func revoke() throws {
        let doc = try service.add(draft(), file: file())
        let name = try #require(doc.localFileName)
        let id = doc.id
        service.revokeAccess(documentId: id)
        #expect(!store.exists(name))
        #expect(service.liveDocuments().isEmpty)
        #expect(ops().isEmpty, "отозванный доступ нельзя вернуть операцией из очереди")
    }

    @Test("Файлы без записей удаляются")
    func orphans() throws {
        let doc = try service.add(draft(), file: file())
        let stray = try store.save(pdfBytes, documentId: UUID(), kind: .pdf)
        service.cleanOrphans()
        #expect(!store.exists(stray))
        #expect(store.exists(doc.localFileName))
    }

    @Test("Поиск: название, номер, владелец, категория; без учёта регистра и «ё»")
    func search() throws {
        let a = try service.add(draft("Паспорт · Анна"), file: file())
        var d2 = draft("Страховка квартиры"); d2.category = .home; d2.number = "ВВВ 1234"
        let b = try service.add(d2, file: file())
        let docs = [a, b]
        let owners = [other: "Соня"]
        #expect(DocumentSearch.filter(docs, query: "ПАСПОРТ").map(\.id) == [a.id])
        #expect(DocumentSearch.filter(docs, query: "вВв").map(\.id) == [b.id])
        #expect(DocumentSearch.filter(docs, query: "соня", owners: owners).count == 2)
        #expect(DocumentSearch.filter(docs, query: "дом").map(\.id) == [b.id])
        #expect(DocumentSearch.filter(docs, query: "Свидетельство").isEmpty)
        #expect(DocumentSearch.filter(docs, query: "", category: .home).map(\.id) == [b.id])
    }

    @Test("Размеры и склонения как в макете")
    func formatting() {
        #expect(DocumentFormat.size(2_400_000) == "2,4 МБ")
        #expect(DocumentFormat.size(840_000) == "840 КБ")
        #expect(DocumentFormat.size(1_800_000) == "1,8 МБ")
        #expect(DocumentFormat.files(1) == "1 файл")
        #expect(DocumentFormat.files(6) == "6 файлов")
        #expect(DocumentFormat.documents(3) == "3 документа")
        #expect(DocumentFormat.eta(5) == "осталось около 5 секунд")
    }
}

// MARK: Загрузка

actor FakeDocumentAPI: DocumentAPI {
    private(set) var created: [UUID] = []
    private(set) var confirmed: [UUID] = []
    private(set) var newSlots = 0
    var confirmError: DocumentTransferError?
    var createError: DocumentTransferError?

    func setCreateError(_ e: DocumentTransferError?) { createError = e }
    func setConfirmError(_ e: DocumentTransferError?) { confirmError = e }

    func createDocument(_ meta: DocumentUploadMetadata) async throws -> UploadSlot {
        if let createError { throw createError }
        created.append(meta.id)
        return UploadSlot(url: URL(string: "https://storage.example/\(meta.id)")!)
    }
    func newUploadSlot(documentId: UUID) async throws -> UploadSlot { newSlots += 1; return UploadSlot(url: URL(string: "https://storage.example/new")!) }
    func confirmUpload(documentId: UUID) async throws {
        if let confirmError { throw confirmError }
        confirmed.append(documentId)
    }
    func downloadURL(documentId: UUID) async throws -> URL { URL(string: "https://storage.example/dl")! }
}

actor FakeTransfer: StorageTransferring {
    var script: [Result<Void, DocumentTransferError>] = []
    private(set) var uploads = 0
    var hang = false

    func setScript(_ s: [Result<Void, DocumentTransferError>]) { script = s }
    func setHang(_ h: Bool) { hang = h }

    func upload(file: URL, to slot: UploadSlot, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        uploads += 1
        progress(10, 100)
        if hang { try await Task.sleep(for: .seconds(30)) }
        if !script.isEmpty { try script.removeFirst().get() }
        progress(100, 100)
    }
    func download(from url: URL, to destination: URL) async throws {}
}

@MainActor
struct DocumentUploadTests {
    let context: ModelContext
    let store: DocumentFileStore
    let service: DocumentService
    let api = FakeDocumentAPI()
    let transfer = FakeTransfer()
    let coordinator: DocumentUploadCoordinator
    let user = UUID()

    init() {
        context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
        store = DocumentFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("up-\(UUID().uuidString)"))
        service = DocumentService(context: context, familyId: UUID(), userId: user, store: store)
        coordinator = DocumentUploadCoordinator(context: context, store: store, api: api, transfer: transfer)
    }

    private func newDoc() throws -> DocumentRecord {
        var d = DocumentDraft(); d.title = "Справка"
        return try service.add(d, file: DocumentImport.validate(data: pdfBytes, fileName: "spravka.pdf"))
    }

    @Test("Успешная загрузка: создание → загрузка → подтверждение, статус «синхронизирован»")
    func success() async throws {
        let doc = try newDoc()
        coordinator.start(doc.id)
        await coordinator.waitForCompletion(doc.id)
        #expect(coordinator.state(for: doc.id) == .finished)
        #expect(doc.uploadState == .synced)
        #expect(doc.syncStatus == .synced)
        #expect(await api.created == [doc.id])
        #expect(await api.confirmed == [doc.id])
    }

    @Test("Ошибка сети: документ остаётся локально, повтор не создаёт дубликат")
    func failureThenRetry() async throws {
        let doc = try newDoc()
        await transfer.setScript([.failure(.offline)])
        coordinator.start(doc.id)
        await coordinator.waitForCompletion(doc.id)
        guard case .failed(let title, let detail) = coordinator.state(for: doc.id) else { Issue.record("ожидали ошибку"); return }
        #expect(title == "Не удалось загрузить файл")
        #expect(detail == "Проверьте интернет и повторите загрузку.")
        #expect(doc.uploadState == .failed)
        #expect(store.exists(doc.localFileName), "файл сохранён для повтора")

        coordinator.retry(doc.id)
        await coordinator.waitForCompletion(doc.id)
        #expect(coordinator.state(for: doc.id) == .finished)
        #expect(doc.uploadState == .synced)
        #expect(Set(await api.created) == [doc.id], "создание по одному и тому же id — идемпотентно")
        #expect(await transfer.uploads == 2)
    }

    @Test("Просроченная ссылка заменяется новой один раз")
    func expiredSlot() async throws {
        let doc = try newDoc()
        await transfer.setScript([.failure(.slotExpired)])
        coordinator.start(doc.id)
        await coordinator.waitForCompletion(doc.id)
        #expect(coordinator.state(for: doc.id) == .finished)
        #expect(await api.newSlots == 1)
    }

    @Test("Отказ сервера при подтверждении показывается как ошибка")
    func confirmRejected() async throws {
        let doc = try newDoc()
        await api.setConfirmError(.rejected("Размер файла не совпал с заявленным."))
        coordinator.start(doc.id)
        await coordinator.waitForCompletion(doc.id)
        guard case .failed(let title, let detail) = coordinator.state(for: doc.id) else { Issue.record("ожидали ошибку"); return }
        #expect(title == "Файл не прошёл проверку")
        #expect(detail.contains("Размер"))
    }

    @Test("Лимит тарифа на сервере: понятное сообщение")
    func premiumRequired() async throws {
        let doc = try newDoc()
        await api.setCreateError(.premiumRequired)
        coordinator.start(doc.id)
        await coordinator.waitForCompletion(doc.id)
        guard case .failed(let title, _) = coordinator.state(for: doc.id) else { Issue.record("ожидали ошибку"); return }
        #expect(title == "Достигнут лимит бесплатного тарифа")
    }

    @Test("Отмена: запись и локальный файл удаляются, на сервер уходит удаление")
    func cancel() async throws {
        let doc = try newDoc()
        let id = doc.id
        let name = try #require(doc.localFileName)
        await transfer.setHang(true)
        coordinator.start(id)
        try await Task.sleep(for: .milliseconds(100))
        coordinator.cancel(id)
        #expect(coordinator.state(for: id) == nil)
        #expect(service.liveDocuments().isEmpty)
        #expect(!store.exists(name))
        let ops = (try? context.fetch(FetchDescriptor<OutboxOperation>())) ?? []
        #expect(ops.contains { $0.type == .delete && $0.entityId == id })
    }

    @Test("Повторный start во время загрузки не запускает вторую")
    func noDoubleStart() async throws {
        let doc = try newDoc()
        coordinator.start(doc.id)
        coordinator.start(doc.id)
        await coordinator.waitForCompletion(doc.id)
        #expect(await transfer.uploads == 1)
    }
}

// MARK: Блокировка

struct StubAuthenticator: BiometricAuthenticating {
    let result: Bool
    func authenticate(reason: String) async -> Bool { result }
}

@MainActor
struct DocumentsLockTests {
    private func defaults() -> UserDefaults {
        let suite = "lock-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("Без защиты содержимое доступно сразу")
    func disabled() {
        let lock = DocumentsLock(defaults: defaults(), authenticator: StubAuthenticator(result: false))
        #expect(lock.isContentVisible)
    }

    @Test("Включение защиты закрывает документы, успешная проверка открывает")
    func enableAndUnlock() async {
        let lock = DocumentsLock(defaults: defaults(), authenticator: StubAuthenticator(result: true))
        lock.isProtectionEnabled = true
        #expect(!lock.isContentVisible)
        #expect(await lock.unlock())
        #expect(lock.isContentVisible)
        lock.lock()
        #expect(!lock.isContentVisible)
    }

    @Test("Неудачная проверка оставляет документы закрытыми")
    func failedUnlock() async {
        let lock = DocumentsLock(defaults: defaults(), authenticator: StubAuthenticator(result: false))
        lock.isProtectionEnabled = true
        #expect(await lock.unlock() == false)
        #expect(!lock.isContentVisible)
    }

    @Test("Настройка сохраняется между запусками")
    func persists() {
        let d = defaults()
        DocumentsLock(defaults: d, authenticator: StubAuthenticator(result: true)).isProtectionEnabled = true
        let again = DocumentsLock(defaults: d, authenticator: StubAuthenticator(result: true))
        #expect(again.isProtectionEnabled)
        #expect(!again.isContentVisible)
    }
}
