import SwiftUI
import SwiftData

/// Завершённые списки.
struct ShoppingHistoryView: View {
    let members: [MemberRecord]
    @Binding var path: [ShoppingRoute]

    @Query(filter: #Predicate<ShoppingListRecord> { $0.isArchived && $0.deletedAt == nil },
           sort: \ShoppingListRecord.updatedAt, order: .reverse) private var lists: [ShoppingListRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { $0.deletedAt == nil }) private var items: [ShoppingItemRecord]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RYBackButton("Покупки") { if !path.isEmpty { path.removeLast() } }
                Spacer()
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, 8)
            RYScreenHeader(title: "История")

            if lists.isEmpty {
                RYEmptyState(systemImage: "clock.arrow.circlepath", title: "История пуста",
                             message: "Завершённые списки появятся здесь после нажатия «Начать новый список».")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: RYSpacing.m) {
                        ForEach(lists) { list in
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
                    }
                    .padding(.horizontal, RYSpacing.screen)
                    .padding(.bottom, RYSpacing.s)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}
