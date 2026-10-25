import SwiftUI
import SwiftData

public struct RootView: View {
    @State private var tab: MainTab = .overview
    /// Предыдущая вкладка — от неё считается направление сдвига.
    @State private var previousTab: MainTab = .overview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = AppSession()
    @State private var keyboardVisible = false
    /// Диалоги экранов сообщают сюда, чтобы затемнить и плавающую панель вкладок, как в макете.
    @State private var dimming = DialogDimming()
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<MemberRecord> { !$0.isInvited }) private var members: [MemberRecord]
    @Query private var families: [FamilyRecord]

    /// Этапы сплэша: показан → растворяется → убран из иерархии.
    private enum SplashPhase { case visible, dissolving, gone }
    @State private var splash: SplashPhase = RootView.showsSplash ? .visible : .gone

    public init() {}

    /// Сплэш показывается всегда, кроме отладочных запусков (`-RYDemo` без `-RYShowSplash`, `-RYSkipSplash`):
    /// иначе он перекрывал бы экраны в UI-тестах.
    static var showsSplash: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-RYSkipSplash") { return false }
        if args.contains("-RYDemo") && !args.contains("-RYShowSplash") { return false }
        #endif
        return true
    }

    public var body: some View {
        ZStack {
            appContent
                .opacity(splash == .visible ? 0 : 1)
                .scaleEffect(splash == .visible ? 0.97 : 1)
                .accessibilityHidden(splash != .gone)
            if splash != .gone {
                SplashView()
                    .opacity(splash == .visible ? 1 : 0)
                    .blur(radius: splash == .visible ? 0 : 16)
                    .scaleEffect(splash == .visible ? 1 : 1.06)
                    .zIndex(10)
            }
        }
        .task { await runSplash() }
    }

    /// Держит сплэш, затем плавно растворяет его: фон размывается и гаснет, а рабочие экраны проявляются под ним.
    private func runSplash() async {
        guard splash == .visible else { return }
        try? await Task.sleep(for: .seconds(1.9))
        withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 0.9)) { splash = .dissolving }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : 1.0))
        splash = .gone
    }

    @ViewBuilder private var appContent: some View {
        if families.isEmpty { FamilyOnboardingView() } else { mainContent }
    }

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            // Переход между вкладками: старый экран растворяется со сдвигом в сторону, откуда уходим,
            // новый появляется со стороны выбора. Экран неактивной вкладки не остаётся в дереве доступности.
            ZStack {
                screen(for: tab)
                    .id(tab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: RYMotion.tabOffset(distance: tab.index - previousTab.index, reduceMotion: reduceMotion))),
                        removal: .opacity.combined(with: .offset(x: -RYMotion.tabOffset(distance: tab.index - previousTab.index, reduceMotion: reduceMotion)))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Резерв под плавающую панель: кнопки экранов встают над ней, прокрутка не уходит под неё.
            // Обычный отступ, а не safeAreaInset: NavigationStack не передаёт внутрь вставки предка.
            .padding(.bottom, keyboardVisible ? 0 : RYSpacing.tabBarReserve)
            if !keyboardVisible { MainTabBar(selection: tab, onSelect: select, isDimmed: dimming.isActive).padding(.bottom, 2) }
        }
        .background(RYColor.background.ignoresSafeArea())
        #if DEBUG
        .overlay(alignment: .topLeading) {
            // Только для UI-тестов (-RYRefreshProbe): невидимый счётчик запущенных обновлений.
            if ProcessInfo.processInfo.arguments.contains("-RYRefreshProbe") {
                Text("\(session.refreshCount)").font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("debug.refreshCount").accessibilityLabel("\(session.refreshCount)")
            }
        }
        #endif
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
        .environment(dimming)
        .onChange(of: members.map(\.id), initial: true) { _, _ in bootstrapSession() }
    }
}

extension RootView {
    @ViewBuilder
    private func screen(for tab: MainTab) -> some View {
        switch tab {
        case .overview:
            OverviewView(onOpenTasks: { select(.tasks) }, onOpenDocuments: { select(.documents) }, onOpenShopping: { select(.shopping) })
        case .shopping: ShoppingView()
        case .tasks: TasksView()
        case .documents: DocumentsView()
        }
    }

    /// Переключает вкладку с анимацией; панель и контент двигаются в одной транзакции.
    private func select(_ new: MainTab) {
        guard new != tab else { return }
        previousTab = tab
        withAnimation(RYMotion.tab(reduceMotion: reduceMotion)) { tab = new }
    }

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
