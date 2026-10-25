import SwiftUI
import SwiftData

/// Хранилище документов: поиск, «полочки» по категориям, недавние файлы и вход в добавление.
struct DocumentsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<DocumentRecord> { $0.deletedAt == nil }, sort: \DocumentRecord.createdAt, order: .reverse)
    private var docs: [DocumentRecord]
    @Query(sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query private var families: [FamilyRecord]

    @State private var path: [DocumentRoute] = []
    @State private var query = ""
    @State private var draft = DocumentDraft()
    @State private var pickedFile: ImportedFile?
    @State private var pendingFilePicker = false

    private var lock: DocumentsLock { session.documentsLock }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var ownerNames: [UUID: String] { Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) }) }
    private var results: [DocumentRecord] { DocumentSearch.filter(docs, query: query, owners: ownerNames) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if lock.isContentVisible { content } else { LockedDocumentsView() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DocumentRoute.self) { route in destination(route) }
        }
    }

    @ViewBuilder
    private func destination(_ route: DocumentRoute) -> some View {
        switch route {
        case .add:
            DocumentFormView(mode: .create, draft: $draft, pickedFile: $pickedFile, pendingFilePicker: $pendingFilePicker,
                             members: members, familyName: families.first?.name ?? "", isPremium: families.first?.isPremium ?? false,
                             path: $path)
        case .edit(let id):
            DocumentFormView(mode: .edit(id), draft: $draft, pickedFile: $pickedFile, pendingFilePicker: $pendingFilePicker,
                             members: members, familyName: families.first?.name ?? "", isPremium: families.first?.isPremium ?? false,
                             path: $path)
        case .cameraDenied:
            CameraDeniedView(draft: $draft, pickedFile: pickedFile, storedCount: docs.count, members: members,
                             pendingFilePicker: $pendingFilePicker, path: $path)
        case .upload(let id):
            DocumentUploadView(documentId: id, members: members, storedCount: docs.count, path: $path)
        case .detail(let id, let added):
            DocumentDetailView(documentId: id, justAdded: added, members: members, familyName: families.first?.name ?? "",
                               allDocs: docs, path: $path, onEdit: { startEdit($0) })
        case .list(let category):
            DocumentListView(category: category, members: members, path: $path)
        case .viewer(let id):
            DocumentViewerView(documentId: id, path: $path)
        }
    }

    // MARK: Содержимое

    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.l) {
                    if docs.isEmpty { emptyStorage } else {
                        RYSearchField(text: $query)
                        if isSearching { searchResults } else { shelves }
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: RYSpacing.s) {
                Text("Документы").font(.system(size: 30, weight: .semibold)).foregroundStyle(RYColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: startAdd) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(RYColor.accent, in: Circle())
                }
                .accessibilityLabel("Добавить документ")
                .accessibilityIdentifier("documents.plus")
            }
            Text(docs.isEmpty ? "Ваше семейное хранилище" : "Важное всегда под рукой · \(DocumentFormat.files(docs.count))")
                .ryFont(.body).foregroundStyle(RYColor.muted)
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.m)
    }

    @ViewBuilder private var bottomBar: some View {
        if isSearching && results.isEmpty {
            Button("Очистить поиск") { query = "" }
                .buttonStyle(.rySecondary).padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
                .background(RYColor.background)
        }
    }

    // MARK: Пустое состояние

    private var emptyStorage: some View {
        VStack(spacing: RYSpacing.m) {
            DocumentsIllustration()
            Text("Важное найдёт\nсвоё место").font(.system(size: 26, weight: .semibold)).foregroundStyle(RYColor.ink)
                .multilineTextAlignment(.center).accessibilityLabel("Важное найдёт своё место")
            Text("Полисы, паспорта и справки — храните всё в одном месте, чтобы не искать в семейной переписке.")
                .ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center).padding(.horizontal, 8)
            Button(action: startAdd) { Label("Добавить первый документ", systemImage: "plus") }
                .buttonStyle(.ryPrimary).accessibilityIdentifier("documents.addFirst")
            Text("Сканируйте камерой или загрузите файл").ryFont(.micro).foregroundStyle(RYColor.muted)
            storageNotice(title: "Только для вашей семьи", text: "Файлы хранятся в зашифрованном виде. Вы решаете, с кем ими поделиться.")
        }
    }

    // MARK: Полочки

    private var shelves: some View {
        VStack(alignment: .leading, spacing: RYSpacing.l) {
            VStack(alignment: .leading, spacing: RYSpacing.s) {
                RYSectionHeader("По полочкам", actionTitle: "Все файлы →") { path.append(.list(nil)) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: RYSpacing.s), GridItem(.flexible())], spacing: RYSpacing.s) {
                    ForEach(DocumentCategory.allCases, id: \.self) { category in
                        CategoryCard(category: category, count: docs.filter { $0.category == category }.count) {
                            path.append(.list(category))
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: RYSpacing.s) {
                RYSectionHeader("Недавно добавлены")
                VStack(spacing: 0) {
                    ForEach(docs.prefix(3)) { doc in
                        DocumentRow(doc: doc) { path.append(.detail(doc.id, added: false)) }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            }
            storageNotice(title: nil, text: "Хранится в зашифрованном виде. Доступ только у вашей семьи.")
            protectionToggle
        }
    }

    private func storageNotice(title: String?, text: String) -> some View {
        DocumentNotice(systemImage: "shield", title: title, text: text)
    }

    private var protectionToggle: some View {
        @Bindable var lock = lock
        return Toggle(isOn: $lock.isProtectionEnabled) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Защита Face ID").ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                Text("Закрывает документы на этом устройстве. Права доступа проверяет сервер.")
                    .ryFont(.micro).foregroundStyle(RYColor.muted)
            }
        }
        .tint(RYColor.accent)
        .padding(14)
        .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
        .accessibilityIdentifier("documents.protection")
    }

    // MARK: Поиск

    @ViewBuilder private var searchResults: some View {
        Text("Все категории · найдено \(results.count)").ryFont(.micro).foregroundStyle(RYColor.muted)
        if results.isEmpty {
            VStack(spacing: RYSpacing.m) {
                RYEmptyState(systemImage: "magnifyingglass", title: "Ничего не нашлось",
                             message: "По запросу «\(query)» нет документов. Попробуйте другое название или имя участника семьи.")
                Text("Например: «Полис», «Соня» или «Паспорт». Все \(DocumentFormat.files(docs.count)) остаются в хранилище.")
                    .ryFont(.micro).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(results) { doc in DocumentRow(doc: doc) { path.append(.detail(doc.id, added: false)) } }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
        }
    }

    // MARK: Действия

    private func startAdd() {
        draft = DocumentDraft()
        draft.ownerId = session.userId
        pickedFile = nil
        path.append(.add)
        #if DEBUG
        if DemoDocuments.prefillsFile, let sample = DemoDocuments.sampleFile() {
            pickedFile = sample
            draft.title = "Справка для танцев · Соня"
            draft.category = .health
            draft.ownerId = members.first { $0.displayName == "Соня" }?.id ?? session.userId
        }
        #endif
    }

    private func startEdit(_ doc: DocumentRecord) {
        draft = DocumentDraft(doc)
        path.append(.edit(doc.id))
    }
}

/// Экран блокировки: документы закрыты до подтверждения Face ID (или код-пароля).
struct LockedDocumentsView: View {
    @Environment(AppSession.self) private var session
    @State private var failed = false

    var body: some View {
        VStack(spacing: RYSpacing.m) {
            Spacer()
            RYEmptyState(systemImage: "lock", title: "Документы защищены",
                         message: failed ? "Не удалось подтвердить личность. Попробуйте ещё раз." : "Подтвердите вход с помощью Face ID или кода-пароля устройства.",
                         actionTitle: "Разблокировать") { Task { await unlock() } }
            Spacer()
        }
        .background(RYColor.background)
        .task { await unlock() }
        .accessibilityIdentifier("documents.locked")
    }

    private func unlock() async { failed = !(await session.documentsLock.unlock()) }
}
