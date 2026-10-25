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

import SwiftData

extension AppSession {
    /// Сервис дел для текущего пользователя; nil, пока вход не выполнен.
    func taskService(context: ModelContext) -> TaskService? {
        guard let familyId, let userId else { return nil }
        return TaskService(context: context, familyId: familyId, userId: userId,
                           reminders: SystemReminderScheduler())
    }
}
