import SwiftUI

public struct RootView: View {
    @State private var tab: MainTab = .overview

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .overview: OverviewView(onOpenTasks: { tab = .tasks }, onOpenDocuments: { tab = .documents })
                case .shopping: PlaceholderScreen(title: "Покупки")
                case .tasks: PlaceholderScreen(title: "Дела семьи")
                case .documents: PlaceholderScreen(title: "Документы")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            MainTabBar(selection: $tab)
        }
        .background(RYColor.background.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

struct PlaceholderScreen: View {
    let title: String
    var body: some View {
        Text(title).ryFont(.title).foregroundStyle(RYColor.ink)
    }
}
