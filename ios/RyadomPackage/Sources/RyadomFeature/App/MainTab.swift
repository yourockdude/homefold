import SwiftUI

public enum MainTab: String, CaseIterable, Identifiable, Sendable {
    case overview, shopping, tasks, documents

    public var id: String { rawValue }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

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

/// Плавающая панель вкладок: матовая капсула 66 pt. Подсветка активной вкладки «переезжает» между вкладками
/// пружиной, иконка слегка подпрыгивает, выбор сопровождается лёгким тактильным откликом.
struct MainTabBar: View {
    let selection: MainTab
    let onSelect: (MainTab) -> Void
    /// Под диалогом панель затемняется вместе с экраном.
    var isDimmed = false

    @Namespace private var highlight
    @State private var bounce: [MainTab: Int] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                let selected = selection == tab
                Button {
                    guard !selected else { return }
                    bounce[tab, default: 0] += 1
                    onSelect(tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .light))
                            .frame(height: 24)
                            .symbolEffect(.bounce.up.byLayer, options: .speed(1.2), value: reduceMotion ? 0 : bounce[tab, default: 0])
                        Text(tab.title)
                            .ryFont(selected ? RYType.bodyXXSB : RYType.bodyXXSM)
                    }
                    .foregroundStyle(selected ? RYColor.accent : RYColor.muted)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        if selected {
                            Capsule().fill(RYColor.accentTint)
                                .matchedGeometryEffect(id: "tab-highlight", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(TabPressStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
            }
        }
        .padding(5)
        .frame(height: 66)
        .ryGlass(in: Capsule())
        .overlay { if isDimmed { Capsule().fill(RYColor.scrim).allowsHitTesting(false) } }
        .animation(.easeOut(duration: 0.2), value: isDimmed)
        .sensoryFeedback(.selection, trigger: selection)
        .padding(.horizontal, 16)
    }
}

/// Лёгкое «вдавливание» вкладки при нажатии.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
