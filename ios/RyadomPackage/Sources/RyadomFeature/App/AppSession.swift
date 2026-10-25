import Foundation
import Observation

/// Текущий пользователь и семья. После этапа «Вход и семья» заполняется из авторизации;
/// до него — из локальной базы (см. RootView).
@Observable
@MainActor
public final class AppSession {
    public var userId: UUID?
    public var familyId: UUID?
    /// Отправка документов на сервер. nil, пока нет входа и сетевого клиента: документы остаются «Ожидает синхронизации».
    public var uploads: DocumentUploadCoordinator?
    /// Состояние загрузки обзора. Локальная база — источник данных; офлайн и ошибка выставляются слоем синхронизации.
    public var overviewState: OverviewLoadState = .loaded
    /// Повторная загрузка. Подключается слоем синхронизации; без него остаётся прежнее состояние.
    public var refreshHandler: (@MainActor () async -> OverviewLoadState)?
    public let documentsLock: DocumentsLock
    public let fileStore = DocumentFileStore()

    public init(userId: UUID? = nil, familyId: UUID? = nil, documentsLock: DocumentsLock? = nil) {
        self.userId = userId
        self.familyId = familyId
        self.documentsLock = documentsLock ?? DocumentsLock(authenticator: AppSession.makeAuthenticator())
    }

    private static func makeAuthenticator() -> any BiometricAuthenticating {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-RYSkipBiometrics") { return ApprovingAuthenticator() }
        #endif
        return SystemBiometricAuthenticator()
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

extension AppSession {
    func documentService(context: ModelContext, isPremium: Bool) -> DocumentService? {
        guard let familyId, let userId else { return nil }
        return DocumentService(context: context, familyId: familyId, userId: userId, store: fileStore, isPremium: isPremium)
    }
}

#if DEBUG
/// Только для UI-тестов и отладки: Face ID подтверждается без системного диалога.
struct ApprovingAuthenticator: BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool { true }
}
#endif

/// Состояние экрана «Обзор»: первая загрузка, готово, нет связи (данные сохранены), ошибка.
public enum OverviewLoadState: Equatable, Sendable {
    case loading
    case loaded
    case offline(lastSync: Date?)
    case failed(lastSync: Date?)
}

extension AppSession {
    /// Повторяет загрузку. Если обработчика нет (сервер не подключён) — состояние не меняется.
    func refreshOverview() async {
        let previous = overviewState
        overviewState = .loading
        if let refreshHandler { overviewState = await refreshHandler() } else {
            try? await Task.sleep(for: .milliseconds(500))
            overviewState = previous
        }
    }
}
