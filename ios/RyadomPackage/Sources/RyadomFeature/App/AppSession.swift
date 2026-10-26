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
    /// Сколько раз запускалось обновление (pull-to-refresh). Нужен для отладки и тестов.
    public internal(set) var refreshCount = 0
    /// Повторная загрузка. Подключается слоем синхронизации; без него остаётся прежнее состояние.
    public var refreshHandler: (@MainActor () async -> OverviewLoadState)?
    /// Планировщик локальных напоминаний. В тестах подменяется заглушкой: `UNUserNotificationCenter` требует приложения.
    public var reminders: any ReminderScheduling = SystemReminderScheduler()
    public let documentsLock: DocumentsLock
    public let settings = AppSettings()
    /// Подписка HomeFold Plus. В отладочных запусках с `-RYDemo` или `-RYSimulatedStore` магазин симулируется.
    public let subscription: SubscriptionStore
    /// Куда перейти после выбора результата поиска: раздел-получатель забирает это и открывает экран.
    public var pendingDestination: SearchDestination?
    /// Где хранится дата начала пробного периода. Keychain переживает переустановку; в отладочных запусках — память.
    public let trialStore: any TrialStoring
    public let fileStore = DocumentFileStore()

    public init(userId: UUID? = nil, familyId: UUID? = nil, documentsLock: DocumentsLock? = nil,
                trialStore: (any TrialStoring)? = nil) {
        self.userId = userId
        self.familyId = familyId
        self.documentsLock = documentsLock ?? DocumentsLock(authenticator: AppSession.makeAuthenticator())
        self.subscription = SubscriptionStore(provider: AppSession.makeSubscriptionProvider())
        self.trialStore = trialStore ?? AppSession.makeTrialStore()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-RYClearSearchHistory") { SearchHistory.clear() }
        #endif
    }

    private static func makeTrialStore() -> any TrialStoring {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-RYDemo") || args.contains("-RYFreshInstall") || args.contains("-RYSimulatedStore") { return InMemoryTrialStore() }
        #endif
        return KeychainTrialStore()
    }

    private static func makeSubscriptionProvider() -> any SubscriptionProviding {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-RYDemo") || args.contains("-RYSimulatedStore") { return SimulatedSubscriptionProvider() }
        #endif
        return StoreKitSubscriptionProvider()
    }

    private static func makeAuthenticator() -> any BiometricAuthenticating {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-RYSkipBiometrics") { return ApprovingAuthenticator() }
        if ProcessInfo.processInfo.arguments.contains("-RYDenyBiometrics") { return DenyingAuthenticator() }
        #endif
        return SystemBiometricAuthenticator()
    }
}

import SwiftData

extension AppSession {
    /// Сервис дел для текущего пользователя; nil, пока вход не выполнен.
    func taskService(context: ModelContext) -> TaskService? {
        guard let familyId, let userId else { return nil }
        return TaskService(context: context, familyId: familyId, userId: userId, reminders: reminders,
                           settings: settings.notifications)
    }
}

extension AppSession {
    func documentService(context: ModelContext) -> DocumentService? {
        guard let familyId, let userId else { return nil }
        return DocumentService(context: context, familyId: familyId, userId: userId, store: fileStore)
    }
}

#if DEBUG
/// Только для UI-тестов и отладки: Face ID подтверждается без системного диалога.
struct ApprovingAuthenticator: BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool { true }
}

/// Только для UI-тестов и отладки: Face ID всегда отклоняется (экран блокировки остаётся).
struct DenyingAuthenticator: BiometricAuthenticating {
    func authenticate(reason: String) async -> Bool { false }
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

extension AppSession {
    /// Приводит тариф семьи в соответствие с подпиской этого устройства (только администратор).
    func reconcilePlan(context: ModelContext) {
        guard subscription.hasCheckedEntitlement, let familyId, let userId else { return }
        let family = (try? context.fetch(FetchDescriptor<FamilyRecord>(predicate: #Predicate { $0.id == familyId })))?.first
        guard let family else { return }
        try? FamilyService(context: context).applyPlus(subscription.entitlement, to: family, by: userId)
    }
}

extension AppSession {
    /// Фиксирует начало пробного периода для семьи, если его ещё не было. Дата берётся из хранилища: после переустановки
    /// действует прежняя, а не новая.
    func ensureTrialStarted(context: ModelContext) {
        guard let familyId else { return }
        let family = (try? context.fetch(FetchDescriptor<FamilyRecord>(predicate: #Predicate { $0.id == familyId })))?.first
        guard let family, family.trialStartedAt == nil else { return }
        family.trialStartedAt = trialStore.begin(at: .now)
        try? context.save()
    }
}
