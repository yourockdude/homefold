import Foundation
import SwiftData

@Model
public final class FamilyRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var plan: String
    /// Тариф выставлен локально после покупки на этом устройстве. Пока нет сервера, только такой тариф можно снять,
    /// когда подписка закончилась; тариф, пришедший с сервера, локально не трогаем.
    public var planIsLocal: Bool = false
    /// Когда начался пробный период (14 дней полного доступа). nil — ещё не зафиксирован.
    public var trialStartedAt: Date?
    public var version: Int
    public var updatedAt: Date

    public init(id: UUID, name: String, plan: String = "free", version: Int = 1, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.plan = plan
        self.version = version
        self.updatedAt = updatedAt
    }

}

@Model
public final class MemberRecord {
    @Attribute(.unique) public var id: UUID
    public var familyId: UUID
    public var displayName: String
    public var role: String
    public var toneIndex: Int
    /// Приглашён, но ещё не принял приглашение: на сервере это приглашение, а не участник.
    public var isInvited: Bool = false
    /// Ссылка-приглашение. Выдаёт сервер и показывает один раз; до синхронизации nil.
    public var inviteURL: String?
    /// Фото профиля: квадратный JPEG ~320 px. nil — показывается буква на цветном фоне.
    @Attribute(.externalStorage) public var avatarData: Data?

    public init(id: UUID, familyId: UUID, displayName: String, role: String, toneIndex: Int, isInvited: Bool = false) {
        self.isInvited = isInvited
        self.id = id
        self.familyId = familyId
        self.displayName = displayName
        self.role = role
        self.toneIndex = toneIndex
    }

    public var isAdmin: Bool { role == "admin" }
    public var tone: AvatarTone { AvatarTone(rawValue: toneIndex % AvatarTone.allCases.count) ?? .mint }
}
