import Foundation
import Observation

/// Текущий пользователь и семья. После этапа «Вход и семья» заполняется из авторизации;
/// до него — из локальной базы (см. RootView).
@Observable
@MainActor
public final class AppSession {
    public var userId: UUID?
    public var familyId: UUID?

    public init(userId: UUID? = nil, familyId: UUID? = nil) {
        self.userId = userId
        self.familyId = familyId
    }
}
