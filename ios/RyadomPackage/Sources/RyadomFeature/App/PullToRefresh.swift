import SwiftUI
import SwiftData

extension AppSession {
    /// Обновление по жесту «потяни вниз». Если подключена синхронизация (`refreshHandler`) — запускает её и
    /// обновляет состояние обзора. Пока сервера нет, выполняет локальную сверку: достраивает повторяющиеся дела
    /// и пересобирает напоминания. Индикатор не исчезает раньше `minimumDuration`, чтобы не мигать.
    func refresh(context: ModelContext, minimumDuration: Duration = .milliseconds(700)) async {
        let started = ContinuousClock.now
        refreshCount += 1
        if let refreshHandler {
            overviewState = await refreshHandler()
        } else {
            let tasks = taskService(context: context)
            tasks?.extendHorizon()
            await tasks?.reconcileReminders()
        }
        let elapsed = started.duration(to: .now)
        if elapsed < minimumDuration { try? await Task.sleep(for: minimumDuration - elapsed) }
    }
}

private struct PullToRefreshModifier: ViewModifier {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.refreshable { await session.refresh(context: context) }
    }
}

extension View {
    /// Pull-to-refresh для прокручиваемого экрана раздела (системный индикатор и действие для VoiceOver).
    func ryPullToRefresh() -> some View { modifier(PullToRefreshModifier()) }
}
