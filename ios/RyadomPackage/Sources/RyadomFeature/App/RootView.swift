import SwiftUI
import SwiftData

public struct RootView: View {
    @State private var tab: MainTab = .overview
    @State private var session = AppSession()
    @State private var keyboardVisible = false
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var members: [MemberRecord]

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .overview: OverviewView(onOpenTasks: { tab = .tasks }, onOpenDocuments: { tab = .documents }, onOpenShopping: { tab = .shopping })
                case .shopping: ShoppingView()
                case .tasks: TasksView()
                case .documents: DocumentsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Резерв под плавающую панель: кнопки экранов встают над ней, прокрутка не уходит под неё.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: keyboardVisible ? 0 : RYSpacing.tabBarReserve)
            }
            if !keyboardVisible { MainTabBar(selection: $tab).padding(.bottom, 2) }
        }
        .background(RYColor.background.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .task(id: session.userId) { await refreshTasks() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshTasks() } }
            if phase == .background { session.documentsLock.lock() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in Task { await refreshTasks() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await refreshTasks() } }
        .environment(session)
        .onChange(of: members.map(\.id), initial: true) { _, _ in bootstrapSession() }
        .preferredColorScheme(.light)
    }
}

extension RootView {
    /// Достраивает повторяющиеся дела и пересобирает локальные напоминания: после запуска, возврата в приложение,
    /// смены часового пояса и смены даты.
    private func refreshTasks() async {
        guard let tasks = session.taskService(context: context) else { return }
        tasks.extendHorizon()
        await tasks.reconcileReminders()
    }

    /// Временно, до этапа «Вход и семья»: текущий пользователь — первый администратор в локальной базе.
    private func bootstrapSession() {
        #if DEBUG
        if let state = DemoData.overviewState { session.overviewState = state }
        if DemoData.isRequested, session.uploads == nil {
            session.uploads = DocumentUploadCoordinator(context: context, store: session.fileStore,
                                                        api: SimulatedDocumentAPI(), transfer: SimulatedStorageTransfer())
        }
        #endif
        guard session.userId == nil, let me = members.first(where: \.isAdmin) ?? members.first else { return }
        session.userId = me.id
        session.familyId = me.familyId
    }
}

struct PlaceholderScreen: View {
    let title: String
    var body: some View {
        Text(title).ryFont(.title).foregroundStyle(RYColor.ink)
    }
}
