import SwiftUI
import SwiftData

/// Карточка документа: метаданные, предпросмотр, открытие и передача копии.
struct DocumentDetailView: View {
    let documentId: UUID
    let justAdded: Bool
    let members: [MemberRecord]
    let familyName: String
    let allDocs: [DocumentRecord]
    @Binding var path: [DocumentRoute]
    var onEdit: (DocumentRecord) -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Query private var matches: [DocumentRecord]

    @State private var preview: UIImage?
    @State private var pageCount: Int?
    @State private var confirmDelete = false
    @State private var shareItem: ShareItem?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var revealNumber = false

    init(documentId: UUID, justAdded: Bool, members: [MemberRecord], familyName: String, allDocs: [DocumentRecord],
         path: Binding<[DocumentRoute]>, onEdit: @escaping (DocumentRecord) -> Void) {
        self.documentId = documentId
        self.justAdded = justAdded
        self.members = members
        self.familyName = familyName
        self.allDocs = allDocs
        self._path = path
        self.onEdit = onEdit
        _matches = Query(filter: #Predicate<DocumentRecord> { $0.id == documentId })
    }

    private var doc: DocumentRecord? { matches.first.flatMap { $0.deletedAt == nil ? $0 : nil } }
    private var lock: DocumentsLock { session.documentsLock }
    private var isAuthor: Bool { doc?.authorId == session.userId }
    private var kind: DocumentFileKind { doc.flatMap { DocumentFileKind(mimeType: $0.mimeType) } ?? .pdf }
    private var openTitle: String { kind == .pdf ? "Открыть PDF" : "Открыть фото" }
    private var service: DocumentService? { session.documentService(context: context, isPremium: false) }

    var body: some View {
        VStack(spacing: 0) {
            if let doc {
                topBar(doc)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if justAdded || doc.uploadState != .synced { addedBanner(doc) }
                        Text(doc.title).font(.system(size: 30, weight: .bold)).foregroundStyle(RYColor.ink)
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        metaLine(doc)
                        previewCard(doc)
                        infoGroup(doc)
                        accessLine(doc)
                        if let errorMessage { RYStatusBanner(kind: .error, text: errorMessage) }
                    }
                    .padding(.horizontal, RYSpacing.screen)
                    .padding(.bottom, RYSpacing.m)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
                RYEmptyState(systemImage: "doc", title: "Документа больше нет",
                             message: "Его удалили или у вас больше нет к нему доступа.", actionTitle: "К документам") { path = [] }
                Spacer()
            }
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { if let doc { bottomBar(doc) } }
        .ryConfirm(isPresented: $confirmDelete, title: "Удалить документ?", message: deleteMessage, confirmTitle: "Удалить документ") {
            if let doc { try? service?.delete(doc); path = [] }
        }
        .sheet(item: $shareItem) { item in ActivityView(items: [item.url]).presentationDetents([.medium, .large]) }
        .task(id: lock.isContentVisible) { await loadPreview() }
    }

    // MARK: Верх

    private func topBar(_ doc: DocumentRecord) -> some View {
        HStack {
            RYBackButton("Документы") { if !path.isEmpty { path.removeLast() } }
            Spacer()
            if isAuthor {
                Menu {
                    Button { onEdit(doc) } label: { Label("Редактировать", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить", systemImage: "trash") }
                } label: { RYGlassCircleLabel(systemImage: "ellipsis") }
                    .accessibilityLabel("Действия с документом")
                    .accessibilityIdentifier("document.menu")
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 10)
    }

    @ViewBuilder
    private func addedBanner(_ doc: DocumentRecord) -> some View {
        if doc.uploadState == .synced {
            let inCategory = allDocs.filter { $0.category == doc.category }.count
            RYNotice(systemImage: "checkmark.circle", title: "Документ загружен",
                     text: "В хранилище \(DocumentFormat.files(allDocs.count)) · \(doc.category.title): \(inCategory)")
                .accessibilityIdentifier("document.added")
        } else {
            RYNotice(systemImage: "arrow.triangle.2.circlepath", title: "Ожидает синхронизации",
                     text: "Файл сохранён на устройстве и отправится в хранилище семьи, когда появится связь.")
                .accessibilityIdentifier("document.pending")
        }
    }

    private func metaLine(_ doc: DocumentRecord) -> some View {
        Text([doc.category.title, DocumentFormat.kind(doc),
              pageCount.map { "\($0) \(OverviewView.plural($0, "страница", "страницы", "страниц"))" },
              DocumentFormat.size(doc.sizeBytes)].compactMap { $0 }.joined(separator: " · "))
            .ryFont(.subhead).foregroundStyle(RYColor.muted)
    }

    // MARK: Предпросмотр

    @ViewBuilder
    private func previewCard(_ doc: DocumentRecord) -> some View {
        Group {
            if lock.isContentVisible, let preview {
                Button { open(doc) } label: {
                    ZStack(alignment: .top) {
                        RYColor.surfaceSecondary
                        Image(uiImage: preview).resizable().scaledToFit().frame(width: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 5)).padding(.top, 14)
                    }
                    .frame(height: 210).clipped()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Предпросмотр документа")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "lock").font(.system(size: 24, weight: .light)).foregroundStyle(RYColor.accent)
                    Text("Предпросмотр скрыт").ryFont(.bodyMedium).foregroundStyle(RYColor.ink)
                    Text("Откройте \(kind == .pdf ? "PDF" : "фото"), чтобы увидеть документ").ryFont(.subhead).foregroundStyle(RYColor.muted)
                }
                .frame(maxWidth: .infinity).frame(height: 150)
                .background(RYColor.surfaceSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("document.previewHidden")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RYRadius.cover))
    }

    // MARK: Метаданные

    private func infoGroup(_ doc: DocumentRecord) -> some View {
        let owner = members.first { $0.id == doc.ownerId }
        let author = members.first { $0.id == doc.authorId }
        let added = justAdded ? DocumentFormat.fullDate(doc.createdAt) : RussianDate.dayMonth(doc.createdAt)
        return RYListGroup {
            DocumentPersonRow(member: owner, title: owner?.displayName ?? "Не указано", subtitle: "Кому принадлежит")
            if !doc.number.isEmpty {
                RYListDivider()
                RYValueRow(title: "Номер") {
                    Button { revealNumber.toggle() } label: {
                        Text(revealNumber ? doc.number : DocumentFormat.masked(doc.number)).ryFont(.callout)
                    }
                    .accessibilityLabel(revealNumber ? "Номер: \(doc.number)" : "Номер скрыт")
                    .accessibilityHint(revealNumber ? "Скрыть номер" : "Показать номер")
                    .accessibilityIdentifier("document.number")
                }
            }
            if let expires = doc.expiresAt {
                RYListDivider()
                RYListRow("Действует до", subtitle: DocumentFormat.fullDate(expires), minHeight: 56,
                          leading: { Image(systemName: "calendar").font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24) },
                          trailing: {
                    if expires < .now { Text("истёк").ryFont(.callout).foregroundStyle(RYColor.danger) }
                })
                .accessibilityElement(children: .combine)
            }
            RYListDivider()
            DocumentPersonRow(member: author, title: "\(author?.displayName ?? "Участник") · \(added)",
                              subtitle: Calendar.current.isDateInToday(doc.createdAt) ? "Добавлено сегодня" : "Добавлено")
        }
    }

    private func accessLine(_ doc: DocumentRecord) -> some View {
        let text: String
        switch doc.access {
        case .family: text = justAdded
            ? DocumentFormView.accessTitle(DocumentDraft(doc), members: members, me: doc.authorId)
            : "Доступен семье \(RussianNames.familyGenitive(familyName))"
        case .authorOnly: text = "Доступен только автору"
        case .selected: text = DocumentFormView.accessTitle(DocumentDraft(doc), members: members, me: doc.authorId).replacingOccurrences(of: "Доступ:", with: "Доступен:")
        }
        return DocumentAccessLine(text: text)
    }

    // MARK: Нижние кнопки

    @ViewBuilder
    private func bottomBar(_ doc: DocumentRecord) -> some View {
        VStack(spacing: 4) {
            if justAdded {
                Button("Вернуться к документам") { path = [] }
                    .buttonStyle(.ryLink).accessibilityIdentifier("document.backToList")
                Button { open(doc) } label: { Text(openTitle) }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("document.open")
            } else {
                HStack(spacing: 10) {
                    Button { open(doc) } label: { Text(openTitle) }
                        .buttonStyle(.ryPrimary).accessibilityIdentifier("document.open")
                    Button { Task { await share(doc) } } label: { Text("Поделиться") }
                        .buttonStyle(.rySecondary).disabled(isPreparing).accessibilityIdentifier("document.share")
                }
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 4)
        .background(RYColor.background)
    }

    private var deleteMessage: String {
        guard let doc else { return "" }
        let others = allDocs.filter { $0.id != doc.id }
        let inCategory = others.filter { $0.category == doc.category }.count
        return "«\(doc.title)» будет удалён для всей семьи. Останется \(DocumentFormat.files(others.count)), в категории «\(doc.category.title)» — \(inCategory). Восстановить файл будет нельзя."
    }

    // MARK: Действия

    private func open(_ doc: DocumentRecord) {
        errorMessage = nil
        Task {
            guard await lock.unlock() else { return }
            if service?.fileURL(for: doc) != nil || session.uploads == nil {
                path.append(.viewer(doc.id))
            } else {
                await fetchThenOpen(doc)
            }
        }
    }

    private func fetchThenOpen(_ doc: DocumentRecord) async {
        isPreparing = true
        defer { isPreparing = false }
        do {
            _ = try await session.uploads?.ensureLocalFile(for: doc.id)
            path.append(.viewer(doc.id))
        } catch let error as DocumentTransferError {
            errorMessage = error.userMessage.detail
        } catch {
            errorMessage = "Не удалось скачать файл."
        }
    }

    /// Передаёт копию файла через системное меню; оригинал остаётся в защищённом хранилище.
    private func share(_ doc: DocumentRecord) async {
        errorMessage = nil
        guard await lock.unlock() else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let source: URL
            if let local = service?.fileURL(for: doc) { source = local }
            else if let uploads = session.uploads { source = try await uploads.ensureLocalFile(for: doc.id) }
            else { errorMessage = "Файла нет на этом устройстве."; return }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ShareCopies", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let safe = doc.title.replacingOccurrences(of: "/", with: "-")
            let copy = dir.appendingPathComponent("\(safe).\(kind.fileExtension)")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: source, to: copy)
            shareItem = ShareItem(url: copy)
        } catch {
            errorMessage = "Не удалось подготовить файл."
        }
    }

    private func loadPreview() async {
        guard let doc, lock.isContentVisible, let url = service?.fileURL(for: doc) else { preview = nil; return }
        let kind = self.kind
        let result = await Task.detached(priority: .userInitiated) {
            (DocumentThumbnail.render(url: url, kind: kind, maxWidth: 320), kind == .pdf ? DocumentFormat.pageCount(at: url) : nil)
        }.value
        preview = result.0
        pageCount = result.1
    }
}
