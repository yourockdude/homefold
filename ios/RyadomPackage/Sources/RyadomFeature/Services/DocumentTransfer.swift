import Foundation

public struct DocumentUploadMetadata: Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var fileName: String
    public var mimeType: String
    public var sizeBytes: Int
    public var category: DocumentCategory
    public var ownerId: UUID?
    public var number: String
    public var expiresAt: Date?
    public var access: DocumentAccess
    public var selectedUserIds: [UUID]
}

/// Короткоживущая ссылка на прямую загрузку в приватное хранилище.
public struct UploadSlot: Sendable, Equatable {
    public var url: URL
    public var method: String
    public var headers: [String: String]

    public init(url: URL, method: String = "PUT", headers: [String: String] = [:]) {
        self.url = url
        self.method = method
        self.headers = headers
    }
}

public enum DocumentTransferError: Error, Equatable, Sendable {
    /// Нет связи или сервер недоступен.
    case offline
    /// Ссылка на загрузку истекла.
    case slotExpired
    /// Достигнут лимит тарифа.
    case premiumRequired
    /// Сервер отклонил файл (размер или тип не совпали).
    case rejected(String)
    case server(String)

    public var userMessage: (title: String, detail: String) {
        switch self {
        case .offline: ("Не удалось загрузить файл", "Проверьте интернет и повторите загрузку.")
        case .slotExpired: ("Не удалось загрузить файл", "Ссылка на загрузку устарела. Повторите загрузку.")
        case .premiumRequired: ("Достигнут лимит бесплатного тарифа", "Чтобы добавить файл, освободите место или подключите HomeFold Plus.")
        case .rejected(let message): ("Файл не прошёл проверку", message)
        case .server(let message): ("Не удалось загрузить файл", message)
        }
    }
}

/// Операции с API документов. Реализует сетевой клиент; все вызовы идемпотентны по идентификатору документа.
public protocol DocumentAPI: Sendable {
    /// Создаёт запись (повтор по тому же `id` безопасен) и возвращает ссылку на загрузку.
    func createDocument(_ meta: DocumentUploadMetadata) async throws -> UploadSlot
    /// Новая ссылка для повторной загрузки.
    func newUploadSlot(documentId: UUID) async throws -> UploadSlot
    /// Сервер проверяет, что файл загружен целиком, размер и тип совпадают.
    func confirmUpload(documentId: UUID) async throws
    /// Ссылка на скачивание живёт около двух минут.
    func downloadURL(documentId: UUID) async throws -> URL
}

/// Передача файла напрямую в хранилище по presigned URL.
public protocol StorageTransferring: Sendable {
    func upload(file: URL, to slot: UploadSlot, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws
    func download(from url: URL, to destination: URL) async throws
}

/// Реализация на URLSession. Тело файла не проходит через наш API.
public struct URLSessionStorageTransfer: StorageTransferring {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func upload(file: URL, to slot: UploadSlot, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        var request = URLRequest(url: slot.url)
        request.httpMethod = slot.method
        for (key, value) in slot.headers { request.setValue(value, forHTTPHeaderField: key) }
        let delegate = ProgressDelegate(progress)
        do {
            let (_, response) = try await session.upload(for: request, fromFile: file, delegate: delegate)
            try Self.check(response)
        } catch let error as DocumentTransferError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            throw Self.map(error)
        }
    }

    public func download(from url: URL, to destination: URL) async throws {
        do {
            let (temp, response) = try await session.download(from: url)
            try Self.check(response)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
        } catch let error as DocumentTransferError {
            throw error
        } catch let error as URLError {
            throw Self.map(error)
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw DocumentTransferError.server("Сервер ответил неожиданно.") }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw DocumentTransferError.slotExpired
        case 413: throw DocumentTransferError.rejected("Файл больше 25 МБ.")
        default: throw DocumentTransferError.server("Хранилище ответило ошибкой \(http.statusCode).")
        }
    }

    static func map(_ error: URLError) -> Error {
        if error.code == .cancelled { return CancellationError() }
        return DocumentTransferError.offline
    }

    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let onProgress: @Sendable (Int64, Int64) -> Void
        init(_ onProgress: @escaping @Sendable (Int64, Int64) -> Void) { self.onProgress = onProgress }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            onProgress(totalBytesSent, totalBytesExpectedToSend)
        }
    }
}
