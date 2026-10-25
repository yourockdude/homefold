import SwiftUI

public enum MainTab: String, CaseIterable, Identifiable, Sendable {
    case overview, shopping, tasks, documents

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Обзор"
        case .shopping: "Покупки"
        case .tasks: "Дела"
        case .documents: "Документы"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "house"
        case .shopping: "basket"
        case .tasks: "checkmark.circle"
        case .documents: "folder"
        }
    }
}

/// Нижняя навигация из макета: белая панель, активный раздел в пилюле.
struct MainTabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: .light))
                            .frame(width: 56, height: 29)
                            .background(selection == tab ? RYColor.accentTint : .clear, in: Capsule())
                        Text(tab.title)
                            .ryFont(.micro)
                            .fontWeight(selection == tab ? .semibold : .regular)
                    }
                    .foregroundStyle(selection == tab ? RYColor.accent : RYColor.muted)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(RYColor.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(RYColor.border).frame(height: 1) }
    }
}
