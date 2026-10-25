import SwiftUI
import SwiftData

enum OverviewRoute: Hashable { case settings, family(back: String) }

/// Семейный обзор. Все счётчики считаются из локальной базы; состояния загрузки приходят из `AppSession`.
struct OverviewView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    var onOpenTasks: () -> Void
    var onOpenDocuments: () -> Void
    var onOpenShopping: () -> Void = {}

    @Query private var families: [FamilyRecord]
    @Query(filter: #Predicate<MemberRecord> { !$0.isInvited }, sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { !$0.isBought && $0.deletedAt == nil })
    private var unboughtItems: [ShoppingItemRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { $0.deletedAt == nil }, sort: \ShoppingItemRecord.updatedAt, order: .reverse)
    private var recentItems: [ShoppingItemRecord]
    @Query(filter: #Predicate<TaskOccurrenceRecord> { $0.deletedAt == nil }, sort: \TaskOccurrenceRecord.dueAt)
    private var occurrences: [TaskOccurrenceRecord]
    @Query(filter: #Predicate<DocumentRecord> { $0.deletedAt == nil && $0.expiresAt != nil }, sort: \DocumentRecord.expiresAt)
    private var expiringDocuments: [DocumentRecord]

    @State private var path: [OverviewRoute] = []

    private var state: OverviewLoadState { session.overviewState }
    private var me: MemberRecord? { members.first { $0.id == session.userId } ?? members.first }

    private var todayTasks: [TaskOccurrenceRecord] {
        occurrences.filter { Calendar.current.isDateInToday($0.dueAt) && !$0.isCompleted }
    }
    private var nextDocument: DocumentRecord? {
        expiringDocuments.first { ($0.expiresAt ?? .distantPast) >= .now }
    }
    /// Последнее изменение покупок, сделанное другим участником.
    private var latestShoppingUpdate: (name: String, date: Date)? {
        guard let item = recentItems.first(where: { $0.authorId != session.userId }),
              let author = members.first(where: { $0.id == item.authorId }) else { return nil }
        return (author.displayName, item.updatedAt)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: OverviewRoute.self) { route in
                    switch route {
                    case .settings: SettingsView(onOpenFamily: { path.append(.family(back: "Настройки")) })
                    case .family(let back): FamilyView(backTitle: back)
                    }
                }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    switch state {
                    case .loading: skeleton
                    case .loaded: loaded
                    case .offline(let lastSync): offline(lastSync: lastSync)
                    case .failed(let lastSync): failed(lastSync: lastSync)
                    }
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.top, 8)
                .padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
            .ryPullToRefresh()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .background(RYColor.background.ignoresSafeArea())
    }

    // MARK: Шапка

    private var header: some View {
        HStack {
            BrandMark()
            Spacer()
            Button { path.append(.settings) } label: { profileButtonLabel }
                .buttonStyle(.plain)
                .accessibilityLabel("Настройки профиля")
                .accessibilityIdentifier("overview.profile")
        }
        .frame(minHeight: 38)
    }

    private var profileButtonLabel: some View {
        ZStack(alignment: .bottomTrailing) {
            if let me {
                AvatarView(member: me, diameter: 36)
            } else {
                Image(systemName: "person.crop.circle").font(.system(size: 30, weight: .light)).foregroundStyle(RYColor.accent)
                    .frame(width: 36, height: 36)
            }
            Image(systemName: "gearshape.fill").font(.system(size: 9, weight: .bold))
                .foregroundStyle(RYColor.onAccent)
                .frame(width: 16, height: 16)
                .background(RYColor.accentFill, in: Circle())
                .overlay(Circle().stroke(RYColor.background, lineWidth: 1.5))
                .offset(x: 3, y: 3)
        }
        .frame(width: 44, height: 44, alignment: .trailing)
        .contentShape(Rectangle())
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU"))).uppercased())
                .ryFont(.subhead).foregroundStyle(RYColor.muted)
            Text("\(Self.greeting(for: .now)), \(me?.displayName ?? "")")
                .ryFont(.title).foregroundStyle(RYColor.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Готово

    @ViewBuilder private var loaded: some View {
        greeting
        cover(compact: false)
        summary
        todaySection
        if let update = latestShoppingUpdate {
            Text("Обновление покупок · \(update.name), \(Self.relative(update.date))")
                .ryFont(.caption).foregroundStyle(RYColor.muted)
        }
        if let doc = nextDocument { documentCard(doc) }
    }

    private func cover(compact: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            FamilyCover()
            LinearGradient(colors: [RYColor.coverShade.opacity(0.85), RYColor.coverShade.opacity(0)], startPoint: .bottom, endPoint: .top)
            VStack(alignment: .leading, spacing: 4) {
                Text(families.first?.name ?? "").ryFont(.heading).foregroundStyle(RYColor.onAccent)
                if !compact { Text("Меньше забот. Больше времени вместе.").ryFont(.caption).foregroundStyle(RYColor.onAccent) }
            }
            .padding(18)
        }
        .frame(height: compact ? 102 : 138)
        .clipShape(RoundedRectangle(cornerRadius: RYRadius.cover))
        .contentShape(RoundedRectangle(cornerRadius: RYRadius.cover))
        .onTapGesture { path.append(.family(back: "Обзор")) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Открыть настройки семьи")
        .accessibilityIdentifier("overview.cover")
    }

    private var summary: some View {
        let open = todayTasks.count
        return HStack(spacing: 12) {
            summaryTile(title: "Купить", count: unboughtItems.count,
                        unit: Self.plural(unboughtItems.count, "продукт", "продукта", "продуктов"), icon: "basket")
            summaryTile(title: "Сегодня", count: open,
                        unit: Self.plural(open, "семейное дело", "семейных дела", "семейных дел"), icon: "checkmark.circle")
        }
    }

    private func summaryTile(title: String, count: Int, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).ryFont(.callout).foregroundStyle(RYColor.accent)
                Spacer()
                Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundStyle(RYColor.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(count)").ryFont(.number).foregroundStyle(RYColor.ink)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(RYMotion.snappy, value: count)
                Text(unit).ryFont(.subhead).foregroundStyle(RYColor.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var todaySection: some View {
        RYSectionHeader("Сегодня вместе", actionTitle: "Все дела", action: onOpenTasks)
        if todayTasks.isEmpty {
            RYCard { Text("На сегодня дел нет").ryFont(.callout).foregroundStyle(RYColor.muted) }
        } else {
            taskGroup
        }
    }

    private var taskGroup: some View {
        RYListGroup {
            ForEach(Array(todayTasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                if index > 0 { RYListDivider() }
                HStack(spacing: 12) {
                    Button {
                        let service = session.taskService(context: context)
                        task.isCompleted ? service?.reopen(task) : service?.complete(task)
                    } label: { RYCheckbox(isOn: task.isCompleted).frame(minWidth: 30, minHeight: 44) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task.isCompleted ? "Вернуть в работу: \(task.title)" : "Отметить выполненным: \(task.title)")
                    Button(action: onOpenTasks) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).ryFont(.body).foregroundStyle(RYColor.ink)
                            Text(taskSubtitle(task)).ryFont(.subhead).foregroundStyle(RYColor.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 62)
            }
        }
    }

    private func taskSubtitle(_ task: TaskOccurrenceRecord) -> String {
        let who = members.first { $0.id == task.assigneeId }?.displayName
        let time = task.hasTime ? RussianDate.time(task.dueAt) : "В течение дня"
        return [time, who].compactMap { $0 }.joined(separator: " · ")
    }

    private func documentCard(_ doc: DocumentRecord) -> some View {
        Button(action: onOpenDocuments) {
            RYListGroup {
                HStack(spacing: 12) {
                    Image(systemName: doc.category.systemImage).font(.system(size: 19, weight: .light)).foregroundStyle(RYColor.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(doc.title).ryFont(.body).foregroundStyle(RYColor.ink)
                        if let d = doc.expiresAt {
                            Text("Действует до \(DocumentFormat.fullDate(d))").ryFont(.subhead).foregroundStyle(RYColor.muted)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(RYColor.accent)
                }
                .frame(minHeight: 62)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Первая загрузка

    @ViewBuilder private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            block(width: 120, height: 12, radius: 6)
            block(width: 310, height: 36, radius: 10)
            block(height: 138, radius: RYRadius.cover)
            HStack(spacing: 12) { block(height: 90, radius: RYRadius.card); block(height: 90, radius: RYRadius.card) }
            block(width: 190, height: 24, radius: 8)
            RYListGroup {
                skeletonRow
                RYListDivider()
                skeletonRow
            }
            Text("Загружаем семейное пространство…").ryFont(.callout).foregroundStyle(RYColor.muted)
            block(height: 62, radius: RYRadius.card)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Загружаем семейное пространство")
        .accessibilityIdentifier("overview.loading")
    }

    private func block(width: CGFloat? = nil, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius).fill(RYColor.surfaceSecondary)
            .frame(width: width, height: height).frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            Circle().fill(RYColor.surfaceSecondary).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 6) {
                block(width: 240, height: 14, radius: 5)
                block(width: 80, height: 10, radius: 4)
            }
            Spacer()
        }
        .frame(minHeight: 62)
    }

    // MARK: Нет связи

    @ViewBuilder
    private func offline(lastSync: Date?) -> some View {
        greeting
        RYNotice(systemImage: "wifi.slash", title: "Нет связи · данные сохранены",
                 text: lastSyncText(lastSync) + " Обновим данные, когда появится интернет.",
                 tint: RYColor.peach, ink: RYColor.peachInk)
            .accessibilityIdentifier("overview.offline")
        cover(compact: true)
        summary
        if !todayTasks.isEmpty { taskGroup }
        if let doc = nextDocument {
            Text("Сохранённый документ «\(doc.title)» доступен без сети.").ryFont(.callout).foregroundStyle(RYColor.muted)
        }
    }

    // MARK: Ошибка

    @ViewBuilder
    private func failed(lastSync: Date?) -> some View {
        greeting
        VStack(spacing: 14) {
            RYIllustration(.cloud)
            Text("Не удалось загрузить обзор").ryFont(.number).foregroundStyle(RYColor.ink).multilineTextAlignment(.center)
            Text("Сервис временно недоступен. Семейные данные не потеряны — попробуйте ещё раз чуть позже.")
                .ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("overview.error")
        RYNotice(systemImage: "clock.arrow.circlepath", title: "Последнее обновление · \(lastSync.map { RussianDate.time($0) } ?? "—")",
                 text: "Сохранённые покупки доступны на устройстве. Новые изменения семьи пока не получены.")
            .padding(.top, 20)
    }

    private func lastSyncText(_ date: Date?) -> String {
        guard let date else { return "Синхронизации ещё не было." }
        return "Последняя синхронизация в \(RussianDate.time(date))."
    }

    // MARK: Нижние кнопки

    @ViewBuilder private var bottomBar: some View {
        switch state {
        case .offline:
            Button("Проверить соединение") { Task { await session.refreshOverview() } }
                .buttonStyle(.rySecondary).padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
                .accessibilityIdentifier("overview.check")
        case .failed:
            VStack(spacing: 2) {
                Button("Попробовать снова") { Task { await session.refreshOverview() } }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("overview.retry")
                Button("Открыть сохранённые покупки", action: onOpenShopping).buttonStyle(.ryLink)
                    .accessibilityIdentifier("overview.openShopping")
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s)
        default:
            EmptyView()
        }
    }

    // MARK: Утилиты

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        case 18..<23: "Добрый вечер"
        default: "Доброй ночи"
        }
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: .now)
    }

    /// Русские формы числительных: 1 / 2–4 / 5+.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m100 = n % 100, m10 = n % 10
        if (11...14).contains(m100) { return many }
        switch m10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
