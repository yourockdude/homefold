import SwiftUI
import SwiftData

/// Прогресс загрузки и ошибка с повтором. Файл считается добавленным только после подтверждения сервера.
struct DocumentUploadView: View {
    let documentId: UUID
    let members: [MemberRecord]
    let storedCount: Int
    @Binding var path: [DocumentRoute]

    @Environment(AppSession.self) private var session
    @Query private var matches: [DocumentRecord]

    init(documentId: UUID, members: [MemberRecord], storedCount: Int, path: Binding<[DocumentRoute]>) {
        self.documentId = documentId
        self.members = members
        self.storedCount = storedCount
        self._path = path
        _matches = Query(filter: #Predicate<DocumentRecord> { $0.id == documentId })
    }

    private var doc: DocumentRecord? { matches.first }
    private var state: DocumentUploadCoordinator.State? { session.uploads?.state(for: documentId) }
    /// Сколько файлов уже лежит в хранилище, не считая этого.
    private var stored: Int { max(0, storedCount - 1) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.m) {
                    switch state {
                    case .running(let progress): runningBody(progress)
                    case .failed(let title, let detail): failedBody(title: title, detail: detail)
                    case .finished, nil: ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .onChange(of: state) { _, new in
            if new == .finished { path = Array(path.dropLast()) + [.detail(documentId, added: true)] }
        }
        .navigationBarBackButtonHidden()
    }

    private var topBar: some View {
        HStack(spacing: RYSpacing.s) {
            Button(action: cancel) { Image(systemName: "arrow.left").font(.system(size: 18)).foregroundStyle(RYColor.ink) }
                .accessibilityLabel("Отменить загрузку")
            Text("Загрузка документа").ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.m)
    }

    // MARK: Загрузка идёт

    @ViewBuilder
    private func runningBody(_ progress: DocumentUploadCoordinator.Progress) -> some View {
        Text("Сохраняем важное").font(.system(size: 28, weight: .semibold)).foregroundStyle(RYColor.ink)
            .accessibilityAddTraits(.isHeader)
        Text("Не закрывайте приложение до завершения загрузки.").ryFont(.body).foregroundStyle(RYColor.muted)
        if let doc {
            VStack(alignment: .leading, spacing: 10) {
                fileHeader(doc)
                HStack {
                    Text("Загрузка файла").ryFont(.micro).foregroundStyle(RYColor.accent)
                    Spacer()
                    Text("\(Int((progress.fraction * 100).rounded()))%").ryFont(.section).foregroundStyle(RYColor.accent)
                        .accessibilityIdentifier("upload.percent")
                }
                ProgressView(value: progress.fraction).tint(RYColor.accent)
                    .accessibilityLabel("Загрузка файла").accessibilityValue("\(Int((progress.fraction * 100).rounded())) процентов")
                Text("\(DocumentFormat.decimal(Double(progress.sent) / 1_000_000)) из \(DocumentFormat.decimal(Double(progress.total) / 1_000_000)) МБ · \(DocumentFormat.eta(progress.etaSeconds))")
                    .ryFont(.micro).foregroundStyle(RYColor.muted)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            summaryCard(doc)
            DocumentNotice(systemImage: "lock", title: "Файл ещё не добавлен",
                           text: "Сейчас в хранилище \(DocumentFormat.files(stored)). После загрузки будет \(stored + 1).")
        }
    }

    // MARK: Ошибка

    @ViewBuilder
    private func failedBody(title: String, detail: String) -> some View {
        DocumentNotice(systemImage: "icloud.slash", title: title, text: detail, tint: RYColor.dangerTint, ink: RYColor.danger)
            .accessibilityIdentifier("upload.error")
        if let doc {
            summaryCard(doc, withFile: true)
            Text("Название, категория и доступ сохранены. Повторная загрузка не создаст дубликат.")
                .ryFont(.body).foregroundStyle(RYColor.muted)
            Text("В хранилище по-прежнему \(DocumentFormat.files(stored)). Этот документ ещё не добавлен.")
                .ryFont(.micro).foregroundStyle(RYColor.muted)
        }
    }

    // MARK: Карточки

    private func fileHeader(_ doc: DocumentRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").font(.system(size: 17, weight: .light)).foregroundStyle(RYColor.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                Text("\(doc.fileName) · \(DocumentFormat.kind(doc)) · \(DocumentFormat.size(doc.sizeBytes))")
                    .ryFont(.micro).foregroundStyle(RYColor.muted)
            }
        }
    }

    private func summaryCard(_ doc: DocumentRecord, withFile: Bool = false) -> some View {
        let owner = members.first { $0.id == doc.ownerId }
        let draft = DocumentDraft(doc)
        return VStack(alignment: .leading, spacing: 16) {
            if withFile { fileHeader(doc) }
            summaryRow(icon: doc.category.systemImage, title: doc.category.title, caption: "Категория")
            HStack(spacing: 12) {
                if let owner { AvatarView(name: owner.displayName, tone: owner.tone, diameter: 36) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(owner?.displayName ?? "Не указано").ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                    Text("Кому принадлежит").ryFont(.micro).foregroundStyle(RYColor.muted)
                }
            }
            summaryRow(icon: "person.2", title: doc.access.title,
                       caption: DocumentFormView.accessTitle(draft, members: members, me: doc.authorId).replacingOccurrences(of: "Доступ: ", with: ""))
        }
        .padding(RYSpacing.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
    }

    private func summaryRow(icon: String, title: String, caption: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                Text(caption).ryFont(.micro).foregroundStyle(RYColor.muted)
            }
        }
    }

    // MARK: Кнопки

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: RYSpacing.xs) {
            if case .failed = state {
                Button { session.uploads?.retry(documentId) } label: { Label("Повторить загрузку", systemImage: "arrow.clockwise") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("upload.retry")
                Button("Отменить", action: cancel).ryFont(.bodyMedium).foregroundStyle(RYColor.accent).frame(minHeight: 40)
                    .accessibilityIdentifier("upload.cancel")
            } else {
                Button("Отменить загрузку", action: cancel).buttonStyle(.rySecondary).accessibilityIdentifier("upload.cancel")
                Text("При отмене файл не добавится в хранилище.").ryFont(.micro).foregroundStyle(RYColor.muted)
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
        .background(RYColor.background)
    }

    private func cancel() {
        session.uploads?.cancel(documentId)
        path = []
    }
}
