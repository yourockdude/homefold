import Testing
import Foundation
import SwiftData
import UIKit
@testable import RyadomFeature

@MainActor
struct FamilyServiceTests {
    let context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
    var service: FamilyService { FamilyService(context: context) }

    private func members() -> [MemberRecord] { (try? context.fetch(FetchDescriptor<MemberRecord>())) ?? [] }
    private func outbox(_ entity: SyncEntity) -> [OutboxOperation] {
        ((try? context.fetch(FetchDescriptor<OutboxOperation>())) ?? []).filter { $0.entity == entity }
    }

    @Test func createFamilyMakesCreatorAdmin() throws {
        let (family, me) = try service.createFamily(name: "  Смирновы ", displayName: " Анна ")
        #expect(family.name == "Смирновы")
        #expect(me.displayName == "Анна")
        #expect(me.isAdmin && me.familyId == family.id)
        #expect(outbox(.family).count == 1)
    }

    @Test func createFamilyRequiresBothNames() {
        #expect(throws: FamilyError.emptyName) { try service.createFamily(name: " ", displayName: "Анна") }
        #expect(throws: FamilyError.emptyName) { try service.createFamily(name: "Смирновы", displayName: "") }
        #expect(members().isEmpty)
    }

    @Test func adminInvitesPendingMember() throws {
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        let invited = try service.invite(name: "Михаил", to: family, by: me.id)
        #expect(invited.isInvited && invited.role == "member" && invited.inviteURL == nil)
        #expect(outbox(.invitation).count == 1)
    }

    @Test func memberCannotInviteOrRemove() throws {
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        let other = MemberRecord(id: UUID(), familyId: family.id, displayName: "Соня", role: "member", toneIndex: 1)
        context.insert(other)
        #expect(throws: FamilyError.notAdmin) { try service.invite(name: "Кто-то", to: family, by: other.id) }
        #expect(throws: FamilyError.notAdmin) { try service.remove(me, by: other.id) }
    }

    @Test func freePlanLimitsMembers() throws {
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        try service.invite(name: "Михаил", to: family, by: me.id)
        try service.invite(name: "Соня", to: family, by: me.id)
        #expect(throws: FamilyError.memberLimit(3)) { try service.invite(name: "Ещё", to: family, by: me.id) }
        family.plan = "plus"
        #expect(throws: Never.self) { try service.invite(name: "Ещё", to: family, by: me.id) }
    }

    @Test func removeMemberDeletesAndQueuesOperation() throws {
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        let invited = try service.invite(name: "Михаил", to: family, by: me.id)
        try service.remove(invited, by: me.id)
        #expect(members().count == 1)
        #expect(outbox(.invitation).contains { $0.type == .delete })
    }

    @Test func cannotRemoveSelf() throws {
        let (_, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        #expect(throws: FamilyError.cannotRemoveSelf) { try service.remove(me, by: me.id) }
    }

    @Test func renameChangesNameForAdminOnly() throws {
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        try service.rename(family, to: "Смирновы-Ивановы", by: me.id)
        #expect(family.name == "Смирновы-Ивановы")
        #expect(throws: FamilyError.notAdmin) { try service.rename(family, to: "X", by: UUID()) }
        #expect(throws: FamilyError.emptyName) { try service.rename(family, to: " ", by: me.id) }
    }
}

@MainActor
struct AvatarTests {
    let context = ModelContext(RyadomSchema.makeContainer(inMemory: true))
    var service: FamilyService { FamilyService(context: context) }

    private func photo(_ size: CGSize) -> Data {
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
        return image.pngData()!
    }

    @Test func prepareCropsToSquareAndShrinks() throws {
        let jpeg = try #require(AvatarImage.prepare(photo(CGSize(width: 1600, height: 900))))
        let result = try #require(UIImage(data: jpeg))
        #expect(result.size == CGSize(width: AvatarImage.side, height: AvatarImage.side))
        #expect(jpeg.count <= AvatarImage.maxBytes)
    }

    @Test func prepareRejectsNonImages() {
        #expect(AvatarImage.prepare(Data("не картинка".utf8)) == nil)
    }

    @Test func memberSetsOwnAvatarAndQueuesOperation() throws {
        let (family, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        _ = family
        try service.setAvatar(photo(CGSize(width: 400, height: 400)), for: me, by: me.id)
        #expect(me.avatarData != nil)
        let ops = (try? context.fetch(FetchDescriptor<OutboxOperation>())) ?? []
        #expect(ops.contains { $0.entity == .member && $0.type == .upsert })
    }

    @Test func memberCannotChangeSomeoneElsesAvatar() throws {
        let (family, admin) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        let other = MemberRecord(id: UUID(), familyId: family.id, displayName: "Соня", role: "member", toneIndex: 1)
        let third = MemberRecord(id: UUID(), familyId: family.id, displayName: "Михаил", role: "member", toneIndex: 2)
        context.insert(other); context.insert(third)
        #expect(throws: FamilyError.notAdmin) { try service.setAvatar(photo(CGSize(width: 300, height: 300)), for: third, by: other.id) }
        // Администратор может поставить фото любому участнику.
        try service.setAvatar(photo(CGSize(width: 300, height: 300)), for: third, by: admin.id)
        #expect(third.avatarData != nil)
    }

    @Test func removingAvatarClearsIt() throws {
        let (_, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        try service.setAvatar(photo(CGSize(width: 300, height: 300)), for: me, by: me.id)
        try service.setAvatar(nil, for: me, by: me.id)
        #expect(me.avatarData == nil)
    }

    @Test func invalidPhotoIsRejectedAndKeepsOldAvatar() throws {
        let (_, me) = try service.createFamily(name: "Смирновы", displayName: "Анна")
        try service.setAvatar(photo(CGSize(width: 300, height: 300)), for: me, by: me.id)
        let before = me.avatarData
        #expect(throws: FamilyError.invalidImage) { try service.setAvatar(Data([1, 2, 3]), for: me, by: me.id) }
        #expect(me.avatarData == before)
    }
}
