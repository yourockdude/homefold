import SwiftUI
import SwiftData

/// Режим листа формы товара.
enum ShoppingFormMode: Identifiable {
    case add(ShoppingListRecord)
    case edit(ShoppingItemRecord)

    var id: String {
        switch self {
        case .add(let list): "add-\(list.id)"
        case .edit(let item): "edit-\(item.id)"
        }
    }
}

enum ShoppingRoute: Hashable {
    case history
}

/// Совместные покупки. Данные — из локальной базы, действия — через `ShoppingService`.
struct ShoppingView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<ShoppingListRecord> { !$0.isArchived && $0.deletedAt == nil },
           sort: \ShoppingListRecord.createdAt) private var lists: [ShoppingListRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { $0.deletedAt == nil },
           sort: \ShoppingItemRecord.createdAt) private var allItems: [ShoppingItemRecord]
    @Query(filter: #Predicate<MemberRecord> { !$0.isInvited }, sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query private var families: [FamilyRecord]

    @State private var path: [ShoppingRoute] = []
    @State private var formMode: ShoppingFormMode?
    @State private var boughtExpanded = false
    @State private var confirmClear = false
    @State private var undoItem: ShoppingItemRecord?

    private var list: ShoppingListRecord? { lists.first }
    private var items: [ShoppingItemRecord] { allItems.filter { $0.listId == list?.id } }
    private var active: [ShoppingItemRecord] { items.filter { !$0.isBought } }
    private var bought: [ShoppingItemRecord] { items.filter(\.isBought) }

    private var grouped: [(category: String, items: [ShoppingItemRecord])] {
        let order = ShoppingCategory.allCases.map(\.rawValue)
        return Dictionary(grouping: active, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { (order.firstIndex(of: $0.0) ?? order.count) < (order.firstIndex(of: $1.0) ?? order.count) }
            .map { (category: $0.0, items: $0.1) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ShoppingRoute.self) { _ in
                    ShoppingHistoryView(members: members, path: $path)
                }
        }
        .sheet(item: $formMode) { mode in
            switch mode {
            case .add(let list):
                ItemFormView(mode: .add(list), service: service, members: members)
            case .edit(let item):
                ItemFormView(mode: .edit(item), service: service, members: members, onDeleted: { undoItem = $0 })
            }
        }
        .task { _ = service?.activeList() }
        .ryConfirm(isPresented: $confirmClear, title: "Убрать купленные товары?",
                   message: clearMessage, confirmTitle: "Убрать \(bought.count) \(Self.goods(bought.count))") {
            if let list { service?.clearBought(in: list) }
        }
        .task(id: undoItem?.id) {
            guard undoItem != nil else { return }
            try? await Task.sleep(for: .seconds(ShoppingService.undoWindow))
            undoItem = nil
        }
    }

    private var service: ShoppingService? {
        guard let familyId = session.familyId, let userId = session.userId else { return nil }
        return ShoppingService(context: context, familyId: familyId, userId: userId)
    }

    private var clearMessage: String {
        let names = bought.enumerated().map { index, item in
            index == 0 ? item.name : item.name.prefix(1).lowercased() + item.name.dropFirst()
        }.joined(separator: " и ")
        return "\(names) будут удалены из общего списка. Останется \(active.count) \(Self.goods(active.count)) — все ещё нужно купить. Отменить очистку нельзя."
    }

    // MARK: Состояния экрана

    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    statusCard
                    if items.isEmpty {
                        emptyState
                    } else if active.isEmpty {
                        allBoughtBody
                    } else {
                        activeBody
                    }
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.bottom, RYSpacing.s)
            }
            .scrollIndicators(.hidden)
            .ryPullToRefresh()
            .scrollDismissesKeyboard(.interactively)
        }
        .background(RYColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    private var header: some View {
        RYScreenHeader(title: "Покупки",
                       subtitle: "Общий список семьи \(RussianNames.familyGenitive(families.first?.name ?? ""))") {
            Menu {
                Button { path.append(.history) } label: { Label("История списков", systemImage: "clock.arrow.circlepath") }
                Button { confirmClear = true } label: { Label("Убрать купленные", systemImage: "trash") }
                    .disabled(bought.isEmpty)
                Button { service?.startNewList() } label: { Label("Начать новый список", systemImage: "plus.square.on.square") }
                    .disabled(items.isEmpty)
            } label: {
                RYGlassCircleLabel(systemImage: "ellipsis")
            }
            .accessibilityLabel("Действия со списком")
            .accessibilityIdentifier("shopping.menu")
        }
    }

    // MARK: Карточка статуса

    @ViewBuilder private var statusCard: some View {
        let total = items.count
        let remaining = active.count
        if total == 0 {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "basket").font(.system(size: 17, weight: .light)).foregroundStyle(RYColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Новый список · 0 товаров").ryFont(.callout).fontWeight(.semibold).foregroundStyle(RYColor.accent)
                    Text("Пока никто ничего не добавил.").ryFont(.subhead).foregroundStyle(RYColor.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: RYRadius.card - 4))
            .accessibilityElement(children: .combine)
        } else if remaining == 0 {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "checkmark.circle").font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Всё куплено").ryFont(.headline).foregroundStyle(RYColor.accent)
                        Text("\(total) из \(total) · осталось купить 0").ryFont(.subhead).foregroundStyle(RYColor.accent)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: RYRadius.card - 4))
                .accessibilityElement(children: .combine)
                Capsule().fill(RYColor.accentFill).frame(height: 4).padding(.horizontal, 2).accessibilityHidden(true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Осталось купить \(remaining)").ryFont(.headline).foregroundStyle(RYColor.ink)
                        .contentTransition(.numericText(value: Double(remaining)))
                        .animation(RYMotion.snappy, value: remaining)
                    Spacer()
                    Text("\(bought.count) из \(total)").ryFont(.callout).foregroundStyle(RYColor.muted)
                }
                Text("Всего \(total) \(Self.goods(total))").ryFont(.subhead).foregroundStyle(RYColor.muted)
                ProgressTrack(fraction: Double(bought.count) / Double(max(total, 1)))
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            RYIllustration(.basket).padding(.top, RYSpacing.s)
            Text("Что нужно купить?").ryFont(.heading).foregroundStyle(RYColor.ink)
            Text("Добавьте первый товар. \(Self.nameList(members)) увидят его в общем списке и смогут отметить покупку.")
                .ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
            Text("Можно указать количество, категорию и того, кто зайдёт в магазин.")
                .ryFont(.subhead).foregroundStyle(RYColor.muted).multilineTextAlignment(.center).padding(.top, 24)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: Активные товары

    private var activeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(grouped, id: \.category) { group in
                VStack(alignment: .leading, spacing: 5) {
                    RYGroupCaption(group.category)
                    RYListGroup {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item, isLast: index == group.items.count - 1)
                        }
                    }
                }
            }
            if !bought.isEmpty { boughtBlock }
        }
    }

    private func itemRow(_ item: ShoppingItemRecord, isLast: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { service?.setBought(item, true) }
                    } label: { RYCheckbox(isOn: false).frame(minWidth: 30, minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Отметить купленным: \(item.name)")
                    Button { formMode = .edit(item) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).ryFont(.body).foregroundStyle(RYColor.ink).multilineTextAlignment(.leading)
                            Text(ShoppingFormat.subtitle(item)).ryFont(.subhead).foregroundStyle(RYColor.muted)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Открыть для редактирования")
                }
                .padding(.vertical, 5)
                .frame(minHeight: 52)
                if !isLast { RYListDivider() }
            }
            if item.syncStatus == .pending {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                    .foregroundStyle(RYColor.muted).accessibilityLabel("Ожидает синхронизации")
            } else if item.syncStatus == .failed {
                Image(systemName: "exclamationmark.circle").font(.system(size: 12))
                    .foregroundStyle(RYColor.danger).accessibilityLabel("Не удалось синхронизировать")
            }
            if let m = members.first(where: { $0.id == item.assigneeId }) {
                AvatarView(name: m.displayName, tone: m.tone, diameter: 26)
            }
        }
    }

    // MARK: Купленные

    private var boughtBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { boughtExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .light)).foregroundStyle(RYColor.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Уже в корзине · \(bought.count) из \(items.count)").ryFont(.callout).foregroundStyle(RYColor.muted)
                        if !boughtExpanded {
                            Text(boughtNames).ryFont(.subhead).foregroundStyle(RYColor.muted).lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .medium))
                        .rotationEffect(.degrees(boughtExpanded ? 180 : 0)).foregroundStyle(RYColor.muted)
                }
                .padding(.horizontal, 4).padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(boughtExpanded ? "развёрнуто" : "свёрнуто")
            .accessibilityIdentifier("shopping.boughtToggle")
            if boughtExpanded {
                RYListGroup {
                    ForEach(Array(bought.enumerated()), id: \.element.id) { index, item in
                        boughtRow(item, isLast: index == bought.count - 1)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    /// «Йогурт, бананы»: первое слово как есть, остальные со строчной буквы.
    private var boughtNames: String {
        bought.enumerated().map { index, item in
            index == 0 ? item.name : item.name.prefix(1).lowercased() + item.name.dropFirst()
        }.joined(separator: ", ")
    }

    private func boughtRow(_ item: ShoppingItemRecord, isLast: Bool, showAmount: Bool = true) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation { service?.setBought(item, false) }
            } label: {
                HStack(spacing: 12) {
                    RYCheckbox(isOn: true)
                    Text(showAmount ? "\(item.name) · \(ShoppingFormat.amount(item))" : item.name)
                        .ryFont(.body).foregroundStyle(RYColor.muted).strikethrough()
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Куплено: \(item.name)")
            .accessibilityHint("Вернуть в список")
            if !isLast { RYListDivider(inset: 38) }
        }
    }

    private var allBoughtBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Отличная командная работа. Всё для семейного ужина уже в корзине.")
                .ryFont(.callout).foregroundStyle(RYColor.muted).padding(.top, 4)
            RYListGroup {
                ForEach(Array(bought.enumerated()), id: \.element.id) { index, item in
                    boughtRow(item, isLast: index == bought.count - 1, showAmount: item.quantity != 1 || !item.note.isEmpty || item.unit != ShoppingUnit.piece.rawValue)
                }
            }
            Text("Купленные товары останутся в истории.").ryFont(.subhead).foregroundStyle(RYColor.muted)
        }
    }

    // MARK: Нижняя панель

    private var bottomBar: some View {
        VStack(spacing: RYSpacing.xs) {
            if let undoItem {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(undoItem.name) удалён").ryFont(.callout).fontWeight(.semibold).foregroundStyle(RYColor.ink)
                        Text("\(ShoppingFormat.amount(undoItem)) · можно вернуть").ryFont(.subhead).foregroundStyle(RYColor.muted)
                    }
                    Spacer()
                    Button("Отменить") {
                        service?.undoDelete(undoItem)
                        self.undoItem = nil
                    }
                    .ryFont(.headline).foregroundStyle(RYColor.accent)
                }
                .padding(14)
                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
            if !items.isEmpty && active.isEmpty {
                Button { service?.startNewList() } label: { Text("Начать новый список") }
                    .buttonStyle(.ryPrimary)
                    .accessibilityIdentifier("shopping.newList")
            } else {
                Button {
                    if let list { formMode = .add(list) }
                } label: { Text(items.isEmpty ? "Добавить первый товар" : "Добавить покупку") }
                    .buttonStyle(.ryPrimary)
                    .accessibilityIdentifier("shopping.add")
            }
        }
        .padding(.horizontal, RYSpacing.screen)
        .padding(.bottom, RYSpacing.xs)
        .animation(.easeOut(duration: 0.2), value: undoItem?.id)
    }

    static func goods(_ n: Int) -> String { OverviewView.plural(n, "товар", "товара", "товаров") }

    static func nameList(_ members: [MemberRecord]) -> String {
        let names = members.map(\.displayName)
        guard let last = names.last else { return "Семья" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " и " + last
    }
}

/// Тонкая полоса прогресса: трек #E5EEE8, заливка акцентным цветом.
struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(RYColor.accentTint)
                Capsule().fill(RYColor.accentFill).frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
