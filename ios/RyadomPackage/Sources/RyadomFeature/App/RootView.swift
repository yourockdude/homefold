import SwiftUI
import SwiftData

public struct RootView: View {
    @State private var tab: MainTab = .overview
    @State private var session = AppSession()
    @State private var keyboardVisible = false
    @Query private var members: [MemberRecord]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .overview: OverviewView(onOpenTasks: { tab = .tasks }, onOpenDocuments: { tab = .documents })
                case .shopping: ShoppingView()
                case .tasks: PlaceholderScreen(title: "Дела семьи")
                case .documents: PlaceholderScreen(title: "Документы")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !keyboardVisible { MainTabBar(selection: $tab) }
        }
        .background(RYColor.background.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .environment(session)
        .onChange(of: members.map(\.id), initial: true) { _, _ in bootstrapSession() }
        .preferredColorScheme(.light)
    }
}

extension RootView {
    /// Временно, до этапа «Вход и семья»: текущий пользователь — первый администратор в локальной базе.
    private func bootstrapSession() {
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
