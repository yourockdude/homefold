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

/// Плавающая панель вкладок: матовая капсула 66 pt, активная вкладка — бледно-зелёная капсула.
struct MainTabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                let selected = selection == tab
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .light))
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? RYColor.accent : RYColor.muted)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(selected ? RYColor.accentTint : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(5)
        .frame(height: 66)
        .ryGlass(in: Capsule())
        .padding(.horizontal, 16)
    }
}
