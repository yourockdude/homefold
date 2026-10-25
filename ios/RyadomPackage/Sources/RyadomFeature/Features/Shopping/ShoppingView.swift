import SwiftUI
import SwiftData

/// Совместные покупки. Данные — из локальной базы, действия — через `ShoppingService`.
struct ShoppingView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<ShoppingListRecord> { !$0.isArchived && $0.deletedAt == nil },
           sort: \ShoppingListRecord.createdAt) private var lists: [ShoppingListRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { $0.deletedAt == nil },
           sort: \ShoppingItemRecord.createdAt) private var allItems: [ShoppingItemRecord]
    @Query(sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query private var families: [FamilyRecord]

    @State private var path: [ShoppingRoute] = []
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
                .navigationDestination(for: ShoppingRoute.self) { route in
                    switch route {
                    case .add:
                        if let list { ItemFormView(mode: .add(list), service: service, members: members, path: $path) }
                    case .edit(let id):
                        if let item = allItems.first(where: { $0.id == id }) {
                            ItemFormView(mode: .edit(item), service: service, members: members, path: $path,
                                         onDeleted: { undoItem = $0 })
                        }
                    case .history:
                        ShoppingHistoryView(members: members, path: $path)
                    }
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
        let names = bought.map(\.name).joined(separator: " и ")
        return "\(names) будут удалены из общего списка. Останется \(active.count) \(Self.goods(active.count)) — все ещё нужно купить. Отменить очистку нельзя."
    }

    // MARK: Состояния экрана

    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.m) {
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
                .padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(RYColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Покупки").ryFont(.title).foregroundStyle(RYColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Общий список семьи \(families.first?.name ?? "")")
                    .ryFont(.caption).foregroundStyle(RYColor.muted)
            }
            Spacer()
            Menu {
                Button { path.append(.history) } label: { Label("История списков", systemImage: "clock.arrow.circlepath") }
                Button { confirmClear = true } label: { Label("Убрать купленные", systemImage: "trash") }
                    .disabled(bought.isEmpty)
                Button { service?.startNewList() } label: { Label("Начать новый список", systemImage: "plus.square.on.square") }
                    .disabled(items.isEmpty)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RYColor.ink)
                    .frame(width: 40, height: 40)
                    .background(RYColor.surface, in: Circle())
            }
            .accessibilityLabel("Действия со списком")
            .accessibilityIdentifier("shopping.menu")
        }
        .padding(.horizontal, RYSpacing.screen)
        .padding(.top, RYSpacing.s)
        .padding(.bottom, RYSpacing.m)
    }

    private var statusCard: some View {
        let total = items.count
        let remaining = active.count
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    if total > 0 && remaining == 0 {
                        Text("Всё куплено").ryFont(.heading).foregroundStyle(RYColor.ink)
                        Text("\(total) из \(total) · осталось купить 0").ryFont(.caption).foregroundStyle(RYColor.accent)
                    } else if total == 0 {
                        Label("Новый список · 0 товаров", systemImage: "basket")
                            .ryFont(.bodyMedium).foregroundStyle(RYColor.accent)
                        Text("Пока никто ничего не добавил.").ryFont(.caption).foregroundStyle(RYColor.accent)
                    } else {
                        Text("Осталось купить \(remaining)").ryFont(.section).foregroundStyle(RYColor.accent)
                        Text("Куплено \(bought.count) из \(total)").ryFont(.caption).foregroundStyle(RYColor.accent)
                    }
                }
                Spacer()
                if total > 0 {
                    HStack(spacing: 4) {
                        ForEach(members.prefix(3)) { AvatarView(name: $0.displayName, tone: $0.tone, diameter: 26) }
                    }
                }
            }
            if total > 0 {
                ProgressView(value: Double(bought.count), total: Double(max(total, 1)))
                    .tint(RYColor.accent)
                    .scaleEffect(x: 1, y: 0.7)
                    .accessibilityHidden(true)
            }
        }
        .padding(RYSpacing.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: RYRadius.card))
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: RYSpacing.m) {
            RYEmptyState(
                systemImage: "basket",
                title: "Что нужно купить?",
                message: "Добавьте первый товар. \(Self.nameList(members)) увидят его в общем списке и смогут отметить покупку."
            )
            Text("Можно указать количество, категорию и того, кто зайдёт в магазин.")
                .ryFont(.caption).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
                .padding(.horizontal, RYSpacing.screen)
        }
        .padding(.top, RYSpacing.l)
    }

    private var activeBody: some View {
        VStack(alignment: .leading, spacing: RYSpacing.m) {
            ForEach(grouped, id: \.category) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.category.uppercased()).ryFont(.micro).foregroundStyle(RYColor.muted)
                        .padding(.leading, 2)
                    VStack(spacing: 0) {
                        ForEach(group.items) { item in itemRow(item) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 2)
                    .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
                }
            }
            if !bought.isEmpty { boughtBlock }
        }
    }

    private func itemRow(_ item: ShoppingItemRecord) -> some View {
        HStack(spacing: 11) {
            Button {
                withAnimation { service?.setBought(item, true) }
            } label: { RYCheckbox(isOn: false).padding(.vertical, 14).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Отметить купленным: \(item.name)")
            Button { path.append(.edit(item.id)) } label: {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                        Text(ShoppingFormat.subtitle(item)).ryFont(.micro).foregroundStyle(RYColor.muted)
                    }
                    Spacer(minLength: 0)
                    if item.syncStatus == .pending {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
                            .foregroundStyle(RYColor.muted).accessibilityLabel("Ожидает синхронизации")
                    } else if item.syncStatus == .failed {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 12))
                            .foregroundStyle(RYColor.danger).accessibilityLabel("Не удалось синхронизировать")
                    }
                    if let m = members.first(where: { $0.id == item.assigneeId }) {
                        AvatarView(name: m.displayName, tone: m.tone, diameter: 28)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открыть для редактирования")
        }
        .frame(minHeight: 54)
    }

    private var boughtBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { boughtExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RYColor.accent).frame(width: 23, height: 23)
                        .background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: 8))
                    Text("Уже в корзине · \(bought.count) из \(items.count)")
                        .ryFont(.body).foregroundStyle(RYColor.muted)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12))
                        .rotationEffect(.degrees(boughtExpanded ? 180 : 0)).foregroundStyle(RYColor.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(boughtExpanded ? "развёрнуто" : "свёрнуто")
            .accessibilityIdentifier("shopping.boughtToggle")
            if boughtExpanded {
                VStack(spacing: 0) {
                    ForEach(bought) { item in boughtRow(item) }
                }
                .padding(.horizontal, 14)
                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            } else {
                Text(bought.map(\.name).joined(separator: ", "))
                    .ryFont(.micro).foregroundStyle(RYColor.muted).strikethrough()
                    .padding(.leading, 33)
            }
        }
        .padding(.top, RYSpacing.xs)
    }

    private func boughtRow(_ item: ShoppingItemRecord) -> some View {
        Button {
            withAnimation { service?.setBought(item, false) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(RYColor.accent)
                Text("\(item.name) · \(ShoppingFormat.amount(item))")
                    .ryFont(.body).foregroundStyle(RYColor.muted).strikethrough()
                Spacer()
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Куплено: \(item.name)")
        .accessibilityHint("Вернуть в список")
    }

    private var allBoughtBody: some View {
        VStack(alignment: .leading, spacing: RYSpacing.m) {
            Text("Отличная командная работа. Всё из списка уже в корзине.")
                .ryFont(.body).foregroundStyle(RYColor.muted)
            VStack(spacing: 0) {
                ForEach(bought) { item in boughtRow(item) }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
        }
    }

    // MARK: Нижняя панель

    private var bottomBar: some View {
        VStack(spacing: RYSpacing.xs) {
            if let undoItem {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(undoItem.name) удалён").ryFont(.bodyMedium).foregroundStyle(.white)
                        Text("\(ShoppingFormat.amount(undoItem)) · можно вернуть").ryFont(.micro).foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Button("Отменить") {
                        service?.undoDelete(undoItem)
                        self.undoItem = nil
                    }
                    .ryFont(.bodyMedium).foregroundStyle(.white)
                }
                .padding(RYSpacing.s + 2)
                .background(RYColor.primary, in: RoundedRectangle(cornerRadius: RYRadius.card))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
            if !items.isEmpty && active.isEmpty {
                Button { service?.startNewList() } label: {
                    Label("Начать новый список", systemImage: "plus")
                }
                .buttonStyle(.ryPrimary)
                .accessibilityIdentifier("shopping.newList")
                Text("Купленные товары останутся в истории.").ryFont(.micro).foregroundStyle(RYColor.muted)
            } else {
                Button { path.append(.add) } label: {
                    Label(items.isEmpty ? "Добавить первый товар" : "Добавить покупку", systemImage: "plus")
                }
                .buttonStyle(.ryPrimary)
                .accessibilityIdentifier("shopping.add")
            }
        }
        .padding(.horizontal, RYSpacing.screen)
        .padding(.vertical, RYSpacing.s)
        .background(RYColor.background)
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

enum ShoppingRoute: Hashable {
    case add
    case edit(UUID)
    case history
}
