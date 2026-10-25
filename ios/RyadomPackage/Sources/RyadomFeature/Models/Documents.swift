import Foundation
import SwiftData

/// Значения `rawValue` совпадают с кодами категорий в API.
public enum DocumentCategory: String, Codable, CaseIterable, Sendable {
    case personal, health, home, travel

    public var title: String {
        switch self {
        case .personal: "Личное"
        case .health: "Здоровье"
        case .home: "Дом"
        case .travel: "Поездки"
        }
    }

    public var tone: AvatarTone {
        switch self {
        case .personal: .mint
        case .health: .peach
        case .home: .sky
        case .travel: .lilac
        }
    }

    public var systemImage: String {
        switch self {
        case .personal: "person.crop.rectangle"
        case .health: "heart.text.square"
        case .home: "house"
        case .travel: "airplane"
        }
    }
}

public enum DocumentAccess: String, Codable, CaseIterable, Sendable {
    case authorOnly = "author_only"
    case selected
    case family

    public var title: String {
        switch self {
        case .authorOnly: "Только автор"
        case .selected: "Выбранные участники"
        case .family: "Вся семья"
        }
    }
}

public enum DocumentUploadState: String, Codable, Sendable {
    case synced
    case pendingUpload     // «Ожидает синхронизации»
    case uploading
    case failed
}

@Model
public final class DocumentRecord {
    @Attribute(.unique) public var id: UUID
    public var familyId: UUID
    public var authorId: UUID
    public var ownerId: UUID?
    public var title: String
    public var categoryRaw: String
    public var number: String
    public var expiresAt: Date?
    public var accessRaw: String
    public var sharedWith: [UUID]
    public var mimeType: String
    /// Исходное имя файла («spravka.pdf»).
    public var fileName: String = ""
    public var sizeBytes: Int
    /// Имя файла в защищённом локальном каталоге; nil — файла на устройстве нет.
    public var localFileName: String?
    public var uploadStateRaw: String
    public var createdAt: Date
    public var updatedAt: Date
    public var version: Int
    public var deletedAt: Date?
    public var syncStatusRaw: String

    public init(id: UUID = UUID(), familyId: UUID, authorId: UUID, ownerId: UUID?, title: String,
                category: DocumentCategory, number: String = "", expiresAt: Date? = nil,
                access: DocumentAccess = .family, sharedWith: [UUID] = [], mimeType: String,
                sizeBytes: Int, localFileName: String?, fileName: String = "", createdAt: Date = .now) {
        self.fileName = fileName
        self.id = id
        self.familyId = familyId
        self.authorId = authorId
        self.ownerId = ownerId
        self.title = title
        self.categoryRaw = category.rawValue
        self.number = number
        self.expiresAt = expiresAt
        self.accessRaw = access.rawValue
        self.sharedWith = sharedWith
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.localFileName = localFileName
        self.uploadStateRaw = DocumentUploadState.pendingUpload.rawValue
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.version = 0
        self.syncStatusRaw = SyncStatus.pending.rawValue
    }

    public var category: DocumentCategory {
        get { DocumentCategory(rawValue: categoryRaw) ?? .personal }
        set { categoryRaw = newValue.rawValue }
    }
    public var access: DocumentAccess {
        get { DocumentAccess(rawValue: accessRaw) ?? .family }
        set { accessRaw = newValue.rawValue }
    }
    public var uploadState: DocumentUploadState {
        get { DocumentUploadState(rawValue: uploadStateRaw) ?? .pendingUpload }
        set { uploadStateRaw = newValue.rawValue }
    }
    public var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .pending }
        set { syncStatusRaw = newValue.rawValue }
    }
}
