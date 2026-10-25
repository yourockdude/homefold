import SwiftUI
import SwiftData

/// Хранилище документов: поиск, «полочки» по категориям, недавние файлы и вход в добавление.
struct DocumentsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<DocumentRecord> { $0.deletedAt == nil }, sort: \DocumentRecord.createdAt, order: .reverse)
    private var docs: [DocumentRecord]
    @Query(filter: #Predicate<MemberRecord> { !$0.isInvited }, sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query private var families: [FamilyRecord]

    @State private var path: [DocumentRoute] = []
    @State private var sheet: DocumentSheet?
    @State private var query = ""
    @State private var draft = DocumentDraft()
    @State private var pickedFile: ImportedFile?
    @State private var pendingFilePicker = false

    private var lock: DocumentsLock { session.documentsLock }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var ownerNames: [UUID: String] { Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) }) }
    private var results: [DocumentRecord] { DocumentSearch.filter(docs, query: query, owners: ownerNames) }
    private var familyName: String { families.first?.name ?? "" }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if lock.isContentVisible { content } else { LockedDocumentsView() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DocumentRoute.self) { route in destination(route) }
        }
        .sheet(item: $sheet) { item in
            DocumentFormView(mode: item == .create ? .create : .edit(editId(item)), draft: $draft, pickedFile: $pickedFile,
                             pendingFilePicker: $pendingFilePicker, members: members, familyName: familyName,
                             isPremium: families.first?.isPremium ?? false, storedCount: docs.count,
                             onClose: { sheet = nil },
                             onScanDenied: { sheet = nil; path.append(.cameraDenied) },
                             onFinished: { id in sheet = nil; path.append(.detail(id, added: true)) })
        }
    }

    private func editId(_ item: DocumentSheet) -> UUID {
        if case .edit(let id) = item { return id }
        return UUID()
    }

    @ViewBuilder
    private func destination(_ route: DocumentRoute) -> some View {
        switch route {
        case .cameraDenied:
            CameraDeniedView(draft: $draft, pickedFile: $pickedFile, storedCount: docs.count, members: members,
                             onPickFile: { pendingFilePicker = true; path.removeLast(); sheet = .create }, path: $path)
        case .detail(let id, let added):
            DocumentDetailView(documentId: id, justAdded: added, members: members, familyName: familyName,
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
            RYScreenHeader(title: "Документы",
                           subtitle: docs.isEmpty ? "Ваше семейное хранилище" : "Важное всегда под рукой · \(DocumentFormat.files(docs.count))") {
                RYGlassCircleButton(systemImage: "plus", label: "Добавить документ", action: startAdd)
                    .accessibilityIdentifier("documents.plus")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.s) {
                    if docs.isEmpty { emptyStorage } else {
                        RYSearchField(text: $query)
                        if isSearching { searchResults } else { shelves }
                    }
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
            .ryPullToRefresh()
            .scrollDismissesKeyboard(.interactively)
        }
        .background(RYColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    @ViewBuilder private var bottomBar: some View {
        if docs.isEmpty {
            Button(action: startAdd) { Text("Добавить первый документ") }
                .buttonStyle(.ryPrimary).accessibilityIdentifier("documents.addFirst")
                .padding(.horizontal, RYSpacing.screen).padding(.bottom, 4)
        } else if isSearching && results.isEmpty {
            Button { query = "" } label: { Text("Очистить поиск") }
                .buttonStyle(.rySecondary).accessibilityIdentifier("documents.clearSearch")
                .padding(.horizontal, RYSpacing.screen).padding(.bottom, 4)
        }
    }

    // MARK: Пустое состояние

    private var emptyStorage: some View {
        VStack(spacing: RYSpacing.s) {
            DocumentsIllustration()
            Text("Важное найдёт\nсвоё место").ryFont(.heading).foregroundStyle(RYColor.ink)
                .multilineTextAlignment(.center).accessibilityLabel("Важное найдёт своё место")
            Text("Полисы, паспорта и справки — храните всё в одном месте, чтобы не искать в семейной переписке.")
                .ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
            Text("Сканируйте камерой или загрузите файл").ryFont(.subhead).foregroundStyle(RYColor.muted)
            RYNotice(systemImage: "checkmark.shield", title: "Только для вашей семьи",
                     text: "Файлы хранятся в зашифрованном виде. Вы решаете, с кем ими поделиться.")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Полочки

    private var shelves: some View {
        VStack(alignment: .leading, spacing: RYSpacing.s) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(DocumentCategory.allCases, id: \.self) { category in
                    CategoryCard(category: category, count: docs.filter { $0.category == category }.count) {
                        path.append(.list(category))
                    }
                }
            }
            RYSectionHeader("Недавно добавлены", actionTitle: "Все файлы") { path.append(.list(nil)) }
                .padding(.top, 2)
            DocumentList(docs: Array(docs.prefix(3))) { path.append(.detail($0.id, added: false)) }
            HStack(spacing: 9) {
                Image(systemName: "checkmark.shield").font(.system(size: 18, weight: .light)).foregroundStyle(RYColor.accent)
                Text("Хранится в зашифрованном виде.\nДоступ только у вашей семьи.").ryFont(.subhead).foregroundStyle(RYColor.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Поиск

    @ViewBuilder private var searchResults: some View {
        Text("Все категории · найдено \(results.count)").ryFont(.caption).foregroundStyle(RYColor.muted)
        if results.isEmpty {
            VStack(spacing: RYSpacing.m) {
                RYIllustration(.search).padding(.top, RYSpacing.s)
                Text("Ничего не нашлось").ryFont(.heading).foregroundStyle(RYColor.ink)
                Text("По запросу «\(query)» нет документов. Попробуйте другое название или имя участника семьи.")
                    .ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
                Text("Например: «Полис», «Соня» или «Паспорт». Все \(DocumentFormat.files(docs.count)) остаются в хранилище.")
                    .ryFont(.subhead).foregroundStyle(RYColor.muted).multilineTextAlignment(.center).padding(.top, RYSpacing.s)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            DocumentList(docs: results) { path.append(.detail($0.id, added: false)) }
        }
    }

    // MARK: Действия

    private func startAdd() {
        draft = DocumentDraft()
        draft.ownerId = session.userId
        pickedFile = nil
        #if DEBUG
        if DemoDocuments.prefillsFile, let sample = DemoDocuments.sampleFile() {
            pickedFile = sample
            draft.title = "Справка для танцев · Соня"
            draft.category = .health
            draft.ownerId = members.first { $0.displayName == "Соня" }?.id ?? session.userId
        }
        #endif
        sheet = .create
    }

    private func startEdit(_ doc: DocumentRecord) {
        draft = DocumentDraft(doc)
        sheet = .edit(doc.id)
    }
}

/// Экран блокировки: документы закрыты до подтверждения Face ID (или кода-пароля).
struct LockedDocumentsView: View {
    @Environment(AppSession.self) private var session
    @State private var failed = false

    var body: some View {
        VStack(spacing: RYSpacing.m) {
            Spacer()
            RYEmptyState(illustration: .lock, title: "Документы защищены",
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

