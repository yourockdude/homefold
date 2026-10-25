import SwiftUI
import SwiftData

/// Завершённые списки. Бесплатный тариф показывает последние 30 дней, остальное открывает Plus.
struct ShoppingHistoryView: View {
    let members: [MemberRecord]
    @Binding var path: [ShoppingRoute]

    @Query(filter: #Predicate<ShoppingListRecord> { $0.isArchived && $0.deletedAt == nil },
           sort: \ShoppingListRecord.updatedAt, order: .reverse) private var lists: [ShoppingListRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { $0.deletedAt == nil }) private var items: [ShoppingItemRecord]
    @Query private var families: [FamilyRecord]
    @State private var paywallReason: PaywallReason?

    static let freeHistoryDays = 30
    private var isPremium: Bool { families.first?.isPremium ?? false }
    private var cutoff: Date { Calendar.current.date(byAdding: .day, value: -Self.freeHistoryDays, to: .now) ?? .distantPast }
    /// Что показываем: на free — только последние 30 дней.
    private var visibleLists: [ShoppingListRecord] { isPremium ? lists : lists.filter { $0.updatedAt >= cutoff } }
    private var hiddenCount: Int { lists.count - visibleLists.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RYBackButton("Покупки") { if !path.isEmpty { path.removeLast() } }
                Spacer()
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, 8)
            RYScreenHeader(title: "История")

            if visibleLists.isEmpty && hiddenCount == 0 {
                RYEmptyState(systemImage: "clock.arrow.circlepath", title: "История пуста",
                             message: "Завершённые списки появятся здесь после нажатия «Начать новый список».")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: RYSpacing.m) {
                        ForEach(visibleLists) { list in
                            let listItems = items.filter { $0.listId == list.id }
                            VStack(alignment: .leading, spacing: 5) {
                                RYGroupCaption(list.updatedAt.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))
                                RYListGroup {
                                    if listItems.isEmpty {
                                        RYListRow("Список был пуст", minHeight: 44)
                                    }
                                    ForEach(Array(listItems.enumerated()), id: \.element.id) { index, item in
                                        VStack(spacing: 0) {
                                            HStack(spacing: 12) {
                                                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 20, weight: .light))
                                                    .foregroundStyle(item.isBought ? RYColor.accent : RYColor.checkBorder)
                                                Text("\(item.name) · \(ShoppingFormat.amount(item))")
                                                    .ryFont(.body).foregroundStyle(item.isBought ? RYColor.muted : RYColor.ink)
                                                Spacer()
                                            }
                                            .frame(minHeight: 44)
                                            if index < listItems.count - 1 { RYListDivider(inset: 32) }
                                        }
                                    }
                                }
                            }
                        }
                        if hiddenCount > 0 { hiddenNotice }
                    }
                    .padding(.horizontal, RYSpacing.screen)
                    .padding(.bottom, RYSpacing.s)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .paywall(reason: $paywallReason)
    }

    /// Старые списки скрыты на бесплатном тарифе.
    private var hiddenNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            RYNotice(systemImage: "clock.arrow.circlepath", title: "Старые списки скрыты",
                     text: "На бесплатном тарифе история хранится \(Self.freeHistoryDays) дней. Ещё \(hiddenCount) \(OverviewView.plural(hiddenCount, "список", "списка", "списков")) — в HomeFold Plus.")
            Button { paywallReason = .shoppingLists } label: { Text("Открыть всю историю") }
                .buttonStyle(.rySecondary).accessibilityIdentifier("history.upgrade")
        }
        .accessibilityIdentifier("history.hidden")
    }
}
