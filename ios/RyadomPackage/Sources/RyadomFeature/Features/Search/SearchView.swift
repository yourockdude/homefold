import SwiftUI
import SwiftData

/// Сквозной поиск по делам, покупкам и документам. Открывается с «Обзора» поверх всего приложения.
struct SearchView: View {
    var onSelect: (SearchHit) -> Void
    var onClose: () -> Void

    @Environment(AppSession.self) private var session

    @Query(filter: #Predicate<TaskOccurrenceRecord> { $0.deletedAt == nil }) private var tasks: [TaskOccurrenceRecord]
    @Query(filter: #Predicate<ChecklistItemRecord> { $0.deletedAt == nil }) private var checklist: [ChecklistItemRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { $0.deletedAt == nil }) private var shopping: [ShoppingItemRecord]
    @Query(filter: #Predicate<ShoppingListRecord> { $0.deletedAt == nil }) private var lists: [ShoppingListRecord]
    @Query(filter: #Predicate<DocumentRecord> { $0.deletedAt == nil }) private var documents: [DocumentRecord]
    @Query(filter: #Predicate<MemberRecord> { !$0.isInvited }) private var members: [MemberRecord]

    @State private var query = ""
    @State private var expanded: Set<SearchKind> = []
    @State private var recents = SearchHistory.load()
    @FocusState private var focused: Bool

    private var lock: DocumentsLock { session.documentsLock }
    private var documentsHidden: Bool { lock.isProtectionEnabled && !lock.isContentVisible }
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var terms: [String] { SearchMatcher.terms(query) }

    private var sections: [SearchSection] {
        GlobalSearch.run(query: query, tasks: tasks, checklist: checklist, shopping: shopping, lists: lists,
                         documents: documents, members: members, includeDocuments: !documentsHidden)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
        }
        .background(RYColor.background.ignoresSafeArea())
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in expanded = [] }
    }

    // MARK: Строка поиска

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .regular)).foregroundStyle(RYColor.muted)
                TextField("Покупки, дела, документы", text: $query)
                    .focused($focused)
                    .ryFont(.body).foregroundStyle(RYColor.ink)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("search.field")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(RYColor.muted)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Очистить запрос").accessibilityIdentifier("search.clear")
                }
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(RYColor.surface, in: Capsule())
            Button("Отмена", action: onClose)
                .ryFont(.body).foregroundStyle(RYColor.accent)
                .accessibilityIdentifier("search.cancel")
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 10)
    }

    // MARK: Содержимое

    @ViewBuilder private var content: some View {
        if trimmed.isEmpty {
            idle
        } else {
            let found = sections
            if found.isEmpty {
                VStack(spacing: RYSpacing.m) {
                    Spacer()
                    RYEmptyState(illustration: .search, title: "Ничего не найдено",
                                 message: "Проверьте написание или попробуйте другое слово.")
                    if documentsHidden { lockedNotice.padding(.horizontal, RYSpacing.screen) }
                    Spacer()
                }
            } else {
                results(found)
            }
        }
    }

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RYSpacing.m) {
                if recents.isEmpty {
                    RYEmptyState(illustration: .search, title: "Поиск по HomeFold",
                                 message: "Ищите сразу по покупкам, делам и документам: по названию, заметке, месту или имени участника.")
                        .padding(.top, 40)
                } else {
                    HStack {
                        Text("Недавние запросы").ryFont(.section).foregroundStyle(RYColor.ink)
                        Spacer()
                        Button("Очистить") { SearchHistory.clear(); recents = [] }
                            .ryFont(.callout).foregroundStyle(RYColor.accent).accessibilityIdentifier("search.clearRecents")
                    }
                    RYListGroup {
                        ForEach(Array(recents.enumerated()), id: \.element) { index, recent in
                            if index > 0 { RYListDivider(inset: 36) }
                            Button { query = recent } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 16, weight: .light))
                                        .foregroundStyle(RYColor.muted).frame(width: 24)
                                    Text(recent).ryFont(.body).foregroundStyle(RYColor.ink)
                                    Spacer()
                                }
                                .frame(minHeight: 48).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("search.recent")
                        }
                    }
                }
                if documentsHidden { lockedNotice }
            }
            .padding(.horizontal, RYSpacing.screen)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func results(_ found: [SearchSection]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: RYSpacing.m) {
                ForEach(found) { section in sectionView(section) }
                if documentsHidden { lockedNotice }
            }
            .padding(.horizontal, RYSpacing.screen).padding(.bottom, RYSpacing.m)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionView(_ section: SearchSection) -> some View {
        let isExpanded = expanded.contains(section.kind)
        let shown = isExpanded ? section.hits : Array(section.hits.prefix(GlobalSearch.previewLimit))
        let hidden = section.hits.count - shown.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(section.kind.title).ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                Text("\(section.hits.count)").ryFont(.callout).foregroundStyle(RYColor.muted)
            }
            RYListGroup {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, hit in
                    if index > 0 { RYListDivider(inset: 52) }
                    row(hit)
                }
                if hidden > 0 {
                    RYListDivider()
                    Button { withAnimation(RYMotion.snappy) { _ = expanded.insert(section.kind) } } label: {
                        Text("Показать ещё \(hidden)").ryFont(.callout).foregroundStyle(RYColor.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("search.more.\(section.kind.rawValue)")
                }
            }
        }
    }

    private func row(_ hit: SearchHit) -> some View {
        Button {
            SearchHistory.remember(trimmed)
            focused = false
            onSelect(hit)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: hit.isMuted && hit.kind != .documents ? "checkmark.circle.fill" : hit.kind.systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(hit.isMuted ? RYColor.muted : RYColor.accent)
                    .frame(width: 40, height: 40)
                    .background(RYColor.accentTint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(SearchMatcher.highlighted(hit.title, terms: terms, tint: RYColor.accent))
                        .ryFont(.body).foregroundStyle(hit.isMuted ? RYColor.muted : RYColor.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(hit.subtitle).ryFont(.subhead).foregroundStyle(RYColor.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(RYColor.checkBorder)
            }
            .frame(minHeight: 58).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hit.title). \(hit.kind.title). \(hit.subtitle)")
        .accessibilityIdentifier("search.result")
    }

    private var lockedNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            RYNotice(systemImage: "lock", title: "Документы защищены",
                     text: "Разблокируйте раздел, чтобы искать и в документах.")
            Button { Task { _ = await lock.unlock() } } label: { Text("Разблокировать") }
                .buttonStyle(.rySecondary).accessibilityIdentifier("search.unlock")
        }
    }
}
