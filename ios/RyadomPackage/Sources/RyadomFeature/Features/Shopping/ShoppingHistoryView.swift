import SwiftUI
import SwiftData

/// Завершённые списки. Бесплатный тариф показывает последние 30 дней (см. этап подписок).
struct ShoppingHistoryView: View {
    let members: [MemberRecord]
    @Binding var path: [ShoppingRoute]

    @Query(filter: #Predicate<ShoppingListRecord> { $0.isArchived && $0.deletedAt == nil },
           sort: \ShoppingListRecord.updatedAt, order: .reverse) private var lists: [ShoppingListRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { $0.deletedAt == nil }) private var items: [ShoppingItemRecord]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RYSpacing.s) {
                Button { if !path.isEmpty { path.removeLast() } } label: {
                    Image(systemName: "arrow.left").font(.system(size: 18)).foregroundStyle(RYColor.ink)
                }
                .accessibilityLabel("Назад")
                Text("История покупок").ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.m)

            if lists.isEmpty {
                RYEmptyState(systemImage: "clock.arrow.circlepath", title: "История пуста",
                             message: "Завершённые списки появятся здесь после нажатия «Начать новый список».")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: RYSpacing.m) {
                        ForEach(lists) { list in
                            let listItems = items.filter { $0.listId == list.id }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(list.updatedAt.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))).uppercased())
                                    .ryFont(.micro).foregroundStyle(RYColor.muted)
                                VStack(alignment: .leading, spacing: 8) {
                                    if listItems.isEmpty {
                                        Text("Список был пуст").ryFont(.body).foregroundStyle(RYColor.muted)
                                    }
                                    ForEach(listItems) { item in
                                        HStack {
                                            Image(systemName: item.isBought ? "checkmark" : "circle")
                                                .font(.system(size: 11)).foregroundStyle(RYColor.accent)
                                            Text("\(item.name) · \(ShoppingFormat.amount(item))")
                                                .ryFont(.body).foregroundStyle(item.isBought ? RYColor.muted : RYColor.ink)
                                            Spacer()
                                        }
                                    }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
                            }
                        }
                    }
                    .padding(.horizontal, RYSpacing.screen)
                }
            }
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}
