import Foundation
import SwiftData

@Model
public final class FamilyRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var plan: String
    public var version: Int
    public var updatedAt: Date

    public init(id: UUID, name: String, plan: String = "free", version: Int = 1, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.plan = plan
        self.version = version
        self.updatedAt = updatedAt
    }

    public var isPremium: Bool { plan == "plus" }
}

@Model
public final class MemberRecord {
    @Attribute(.unique) public var id: UUID
    public var familyId: UUID
    public var displayName: String
    public var role: String
    public var toneIndex: Int

    public init(id: UUID, familyId: UUID, displayName: String, role: String, toneIndex: Int) {
        self.id = id
        self.familyId = familyId
        self.displayName = displayName
        self.role = role
        self.toneIndex = toneIndex
    }

    public var isAdmin: Bool { role == "admin" }
    public var tone: AvatarTone { AvatarTone(rawValue: toneIndex % AvatarTone.allCases.count) ?? .mint }
}
