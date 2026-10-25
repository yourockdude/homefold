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

    var body: some View {
        VStack(spacing: 0) {
            if let doc {
                topBar(doc)
                ScrollView {
                    VStack(alignment: .leading, spacing: RYSpacing.m) {
                        if justAdded { addedBanner(doc) }
                        Text(doc.title).font(.system(size: 28, weight: .semibold)).foregroundStyle(RYColor.ink)
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        metaLine(doc)
                        previewCard(doc)
                        infoCard(doc)
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

    private var service: DocumentService? { session.documentService(context: context, isPremium: false) }

    // MARK: Верх

    private func topBar(_ doc: DocumentRecord) -> some View {
        HStack(spacing: RYSpacing.s) {
            Button { if !path.isEmpty { path.removeLast() } } label: {
                Image(systemName: "arrow.left").font(.system(size: 18)).foregroundStyle(RYColor.ink)
            }
            .accessibilityLabel("Назад")
            Text("Документ").ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            if isAuthor {
                Menu {
                    Button { onEdit(doc) } label: { Label("Редактировать", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(RYColor.ink)
                        .frame(width: 40, height: 40).background(RYColor.surface, in: Circle())
                }
                .accessibilityLabel("Действия с документом")
                .accessibilityIdentifier("document.menu")
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.s)
    }

    @ViewBuilder
    private func addedBanner(_ doc: DocumentRecord) -> some View {
        if doc.uploadState == .synced {
            let inCategory = allDocs.filter { $0.category == doc.category }.count
            DocumentNotice(systemImage: "checkmark.circle", title: "Документ загружен",
                           text: "В хранилище \(DocumentFormat.files(allDocs.count)) · \(doc.category.title): \(inCategory)")
                .accessibilityIdentifier("document.added")
        } else {
            DocumentNotice(systemImage: "arrow.triangle.2.circlepath", title: "Сохранено на устройстве",
                           text: "Ожидает синхронизации: файл отправится в хранилище семьи, когда появится связь.")
                .accessibilityIdentifier("document.pending")
        }
    }

    private func metaLine(_ doc: DocumentRecord) -> some View {
        HStack(spacing: 10) {
            Text(doc.category.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(doc.category.tone.ink)
                .padding(.horizontal, 10).padding(.vertical, 6).background(doc.category.tone.background, in: Capsule())
            Text([DocumentFormat.kind(doc), pageCount.map { "\($0) \(OverviewView.plural($0, "страница", "страницы", "страниц"))" },
                  DocumentFormat.size(doc.sizeBytes)].compactMap { $0 }.joined(separator: " · "))
                .ryFont(.micro).foregroundStyle(RYColor.muted)
        }
    }

    // MARK: Предпросмотр

    @ViewBuilder
    private func previewCard(_ doc: DocumentRecord) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if lock.isContentVisible, let preview {
                Button { open(doc) } label: {
                    Image(uiImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity)
                        .frame(height: 200).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Предпросмотр документа")
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13)).foregroundStyle(RYColor.accent)
                    .frame(width: 36, height: 36).background(.white, in: Circle()).padding(12).allowsHitTesting(false)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "lock").font(.system(size: 22, weight: .light)).foregroundStyle(RYColor.accent)
                    Text("Предпросмотр скрыт").ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                    Text("Откройте \(kind == .pdf ? "PDF" : "фото"), чтобы увидеть документ").ryFont(.micro).foregroundStyle(RYColor.muted)
                }
                .frame(maxWidth: .infinity).frame(height: 200)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("document.previewHidden")
            }
        }
        .background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: RYRadius.cover))
    }

    // MARK: Метаданные

    private func infoCard(_ doc: DocumentRecord) -> some View {
        let owner = members.first { $0.id == doc.ownerId }
        let author = members.first { $0.id == doc.authorId }
        return VStack(spacing: 0) {
            if justAdded {
                addedRows(doc, owner: owner, author: author)
            } else {
                infoRow("Кому принадлежит") { Text(owner?.displayName ?? "Не указано").fontWeight(.semibold) }
                if !doc.number.isEmpty { Divider().overlay(RYColor.border); infoRow("Номер") { Text(doc.number).fontWeight(.semibold) } }
                if let expires = doc.expiresAt {
                    Divider().overlay(RYColor.border)
                    infoRow("Действует до") {
                        Text(DocumentFormat.fullDate(expires)).fontWeight(.semibold)
                            .foregroundStyle(expires < .now ? RYColor.danger : RYColor.ink)
                    }
                }
                Divider().overlay(RYColor.border)
                infoRow("Добавлено") {
                    HStack(spacing: 8) {
                        if let author { AvatarView(name: author.displayName, tone: author.tone, diameter: 22) }
                        Text("\(author?.displayName ?? "Участник") · \(RussianDate.dayMonth(doc.createdAt))").fontWeight(.medium)
                    }
                }
            }
        }
        .padding(.horizontal, RYSpacing.m).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
    }

    private func addedRows(_ doc: DocumentRecord, owner: MemberRecord?, author: MemberRecord?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if let owner { AvatarView(name: owner.displayName, tone: owner.tone, diameter: 36) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(owner?.displayName ?? "Не указано").ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                    Text("Кому принадлежит").ryFont(.micro).foregroundStyle(RYColor.muted)
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "person.2").font(.system(size: 16, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(doc.access.title).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                    Text(DocumentFormView.accessTitle(DocumentDraft(doc), members: members, me: doc.authorId)).ryFont(.micro).foregroundStyle(RYColor.muted)
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 16, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(author?.displayName ?? "Участник") · \(DocumentFormat.fullDate(doc.createdAt))").ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                    Text(Calendar.current.isDateInToday(doc.createdAt) ? "Добавлено сегодня" : "Добавлено").ryFont(.micro).foregroundStyle(RYColor.muted)
                }
            }
        }
        .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label).ryFont(.body).foregroundStyle(RYColor.muted)
            Spacer(minLength: 12)
            value().ryFont(.body).foregroundStyle(RYColor.ink).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func accessLine(_ doc: DocumentRecord) -> some View {
        let text: String
        switch doc.access {
        case .family: text = "Доступен семье \(RussianNames.familyGenitive(familyName))"
        case .authorOnly: text = "Доступен только автору"
        case .selected: text = DocumentFormView.accessTitle(DocumentDraft(doc), members: members, me: doc.authorId).replacingOccurrences(of: "Доступ:", with: "Доступен:")
        }
        return Label(text, systemImage: "lock").ryFont(.caption).foregroundStyle(RYColor.muted)
    }

    // MARK: Нижние кнопки

    @ViewBuilder
    private func bottomBar(_ doc: DocumentRecord) -> some View {
        VStack(spacing: RYSpacing.xs) {
            if justAdded {
                Button { open(doc) } label: { Label(openTitle, systemImage: "doc.text") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("document.open")
                Button("Вернуться к документам") { path = [] }
                    .ryFont(.bodyMedium).foregroundStyle(RYColor.accent).frame(minHeight: 40)
                    .accessibilityIdentifier("document.backToList")
            } else {
                HStack(spacing: RYSpacing.s) {
                    Button { open(doc) } label: { Label(openTitle, systemImage: "doc.text") }
                        .buttonStyle(.ryPrimary).accessibilityIdentifier("document.open")
                    Button { Task { await share(doc) } } label: { Label("Поделиться", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.rySecondary).disabled(isPreparing).accessibilityIdentifier("document.share")
                }
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
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
            if session.documentService(context: context, isPremium: false)?.fileURL(for: doc) != nil || session.uploads == nil {
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
