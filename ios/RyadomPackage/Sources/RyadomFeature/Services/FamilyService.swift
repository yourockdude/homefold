import Foundation
import SwiftData

public enum FamilyError: Error, Equatable, LocalizedError {
    case emptyName
    case notAdmin
    case cannotRemoveSelf
    case lastAdmin
    case notFound
    /// Достигнут лимит участников тарифа.
    case memberLimit(Int)
    case invalidImage

    public var errorDescription: String? {
        switch self {
        case .emptyName: "Введите имя."
        case .notAdmin: "Это может сделать только администратор семьи."
        case .cannotRemoveSelf: "Себя из семьи убрать нельзя."
        case .lastAdmin: "Единственного администратора убрать нельзя."
        case .notFound: "Участника уже нет в семье."
        case .memberLimit(let limit): "В семье может быть не более \(limit) участников."
        case .invalidImage: "Не удалось открыть фото. Попробуйте другое."
        }
    }
}

/// Локальные действия над семьёй. Меняют SwiftData и кладут операции в очередь;
/// на сервер они уходят слоем синхронизации (`POST /families`, `/invitations`, `DELETE /families/me/members/{id}`).
@MainActor
public final class FamilyService {
    /// Участников в семье, включая приглашённых.
    public static let memberLimit = 8

    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    /// Первая регистрация: создаёт семью и делает текущего пользователя её администратором.
    @discardableResult
    public func createFamily(name: String, displayName: String) throws -> (family: FamilyRecord, me: MemberRecord) {
        let familyName = clean(name), myName = clean(displayName)
        guard !familyName.isEmpty, !myName.isEmpty else { throw FamilyError.emptyName }
        let family = FamilyRecord(id: UUID(), name: familyName)
        let me = MemberRecord(id: UUID(), familyId: family.id, displayName: myName, role: "admin", toneIndex: 0)
        context.insert(family)
        context.insert(me)
        enqueue(.family, id: family.id, .upsert, version: 0, CreateFamilyPayload(id: family.id, name: familyName, displayName: myName))
        try context.save()
        return (family, me)
    }

    public func rename(_ family: FamilyRecord, to name: String, by actorId: UUID?) throws {
        try requireAdmin(actorId, in: family.id)
        let newName = clean(name)
        guard !newName.isEmpty else { throw FamilyError.emptyName }
        guard newName != family.name else { return }
        family.name = newName
        family.updatedAt = .now
        enqueue(.family, id: family.id, .upsert, version: family.version, RenameFamilyPayload(name: newName))
        try context.save()
    }

    /// Добавляет приглашённого участника. Ссылку-приглашение выдаёт сервер после синхронизации.
    @discardableResult
    public func invite(name: String, to family: FamilyRecord, by actorId: UUID?) throws -> MemberRecord {
        try requireAdmin(actorId, in: family.id)
        let invitedName = clean(name)
        guard !invitedName.isEmpty else { throw FamilyError.emptyName }
        let current = members(of: family.id)
        guard current.count < Self.memberLimit else { throw FamilyError.memberLimit(Self.memberLimit) }
        let member = MemberRecord(id: UUID(), familyId: family.id, displayName: invitedName, role: "member",
                                  toneIndex: current.count, isInvited: true)
        context.insert(member)
        enqueue(.invitation, id: member.id, .upsert, version: 0, InvitePayload(id: member.id, displayName: invitedName))
        try context.save()
        return member
    }

    /// Ставит или убирает (`nil`) фото профиля. Своё фото меняет любой участник, чужое — администратор.
    /// `photo` — любое изображение: оно кадрируется в квадрат и сжимается.
    public func setAvatar(_ photo: Data?, for member: MemberRecord, by actorId: UUID?) throws {
        guard let actorId, actorId == member.id || isAdmin(actorId, in: member.familyId) else { throw FamilyError.notAdmin }
        var prepared: Data?
        if let photo {
            guard let jpeg = AvatarImage.prepare(photo) else { throw FamilyError.invalidImage }
            prepared = jpeg
        }
        member.avatarData = prepared
        enqueue(.member, id: member.id, .upsert, version: 0, AvatarPayload(avatar: prepared))
        try context.save()
    }

    /// Выставляет тариф семьи по подписке этого устройства. Подписку оформляет и подтверждает администратор.
    /// `entitlement == nil` — подписка закончилась: тариф снимается, только если выставляли его мы же.
    /// Последнее слово всегда за сервером: JWS уходит в очередь для `POST /billing/verify`.
    public func applyPlus(_ entitlement: EntitlementInfo?, to family: FamilyRecord, by actorId: UUID?) throws {
        try requireAdmin(actorId, in: family.id)
        if let entitlement {
            guard !family.hasPlan else { return }
            family.plan = "plus"
            family.planIsLocal = true
            family.updatedAt = .now
            enqueue(.subscription, id: family.id, .upsert, version: family.version,
                    SubscriptionPayload(productId: entitlement.productId, signedTransaction: entitlement.signedTransaction))
        } else {
            guard family.hasPlan, family.planIsLocal else { return }
            family.plan = "free"
            family.planIsLocal = false
            family.updatedAt = .now
        }
        try context.save()
    }

    /// Убирает участника из семьи или отзывает приглашение.
    public func remove(_ member: MemberRecord, by actorId: UUID?) throws {
        try requireAdmin(actorId, in: member.familyId)
        guard member.id != actorId else { throw FamilyError.cannotRemoveSelf }
        guard members(of: member.familyId).contains(where: { $0.id == member.id }) else { throw FamilyError.notFound }
        if member.isAdmin, members(of: member.familyId).filter(\.isAdmin).count == 1 { throw FamilyError.lastAdmin }
        enqueue(member.isInvited ? .invitation : .member, id: member.id, .delete, version: 0, EmptyBody())
        context.delete(member)
        try context.save()
    }

    // MARK: Внутреннее

    private struct CreateFamilyPayload: Encodable { let id: UUID; let name: String; let displayName: String }
    private struct RenameFamilyPayload: Encodable { let name: String }
    private struct InvitePayload: Encodable { let id: UUID; let displayName: String }
    private struct EmptyBody: Encodable {}
    private struct SubscriptionPayload: Encodable { let productId: String; let signedTransaction: String }
    private struct AvatarPayload: Encodable { let avatar: Data? }

    private func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func members(of familyId: UUID) -> [MemberRecord] {
        let descriptor = FetchDescriptor<MemberRecord>(predicate: #Predicate { $0.familyId == familyId })
        return (try? context.fetch(descriptor)) ?? []
    }

    private func isAdmin(_ userId: UUID, in familyId: UUID) -> Bool {
        members(of: familyId).contains { $0.id == userId && $0.isAdmin }
    }

    private func requireAdmin(_ actorId: UUID?, in familyId: UUID) throws {
        guard let actorId, members(of: familyId).contains(where: { $0.id == actorId && $0.isAdmin }) else {
            throw FamilyError.notAdmin
        }
    }

    private func enqueue<P: Encodable>(_ entity: SyncEntity, id: UUID, _ type: SyncOperationType, version: Int, _ payload: P) {
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        context.insert(OutboxOperation(entity: entity, entityId: id, type: type, baseVersion: version, payload: data))
    }
}
