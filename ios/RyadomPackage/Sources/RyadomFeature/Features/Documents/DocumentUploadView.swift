import SwiftUI
import SwiftData

/// Прогресс загрузки и ошибка с повтором внутри листа формы. Файл считается добавленным только
/// после подтверждения сервера.
struct DocumentUploadView: View {
    let documentId: UUID
    let members: [MemberRecord]
    let storedCount: Int
    var onCancel: () -> Void
    var onFinished: () -> Void

    @Environment(AppSession.self) private var session
    @Query private var matches: [DocumentRecord]

    init(documentId: UUID, members: [MemberRecord], storedCount: Int, onCancel: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.documentId = documentId
        self.members = members
        self.storedCount = storedCount
        self.onCancel = onCancel
        self.onFinished = onFinished
        _matches = Query(filter: #Predicate<DocumentRecord> { $0.id == documentId })
    }

    private var doc: DocumentRecord? { matches.first }
    private var state: DocumentUploadCoordinator.State? { session.uploads?.state(for: documentId) }
    /// Сколько файлов уже лежит в хранилище, не считая этого.
    private var stored: Int { max(0, storedCount - 1) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Загрузка документа").ryFont(.headline).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                HStack {
                    Button("Отмена", action: onCancel).ryFont(.body).foregroundStyle(RYColor.accent)
                        .accessibilityIdentifier("upload.cancelHeader")
                    Spacer()
                }
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, 22).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.s) {
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
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .onChange(of: state) { _, new in if new == .finished { onFinished() } }
    }

    // MARK: Загрузка идёт

    @ViewBuilder
    private func runningBody(_ progress: DocumentUploadCoordinator.Progress) -> some View {
        Text("Сохраняем важное").font(.system(size: 28, weight: .bold)).foregroundStyle(RYColor.ink)
            .accessibilityAddTraits(.isHeader)
        Text("Не закрывайте приложение до завершения загрузки.").ryFont(.callout).foregroundStyle(RYColor.muted)
        if let doc {
            let percent = Int((progress.fraction * 100).rounded())
            RYListGroup {
                fileRow(doc)
                RYListDivider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Загрузка файла").ryFont(.subhead).foregroundStyle(RYColor.accent)
                        Spacer()
                        Text("\(percent)%").ryFont(.headline).foregroundStyle(RYColor.accent)
                            .accessibilityIdentifier("upload.percent")
                    }
                    ProgressView(value: progress.fraction).tint(RYColor.accent)
                        .accessibilityLabel("Загрузка файла").accessibilityValue("\(percent) процентов")
                    Text("\(DocumentFormat.decimal(Double(progress.sent) / 1_000_000, digits: 2)) из \(DocumentFormat.decimal(Double(progress.total) / 1_000_000)) МБ · \(DocumentFormat.eta(progress.etaSeconds))")
                        .ryFont(.subhead).foregroundStyle(RYColor.muted)
                }
                .padding(.vertical, 12)
            }
            summaryGroup(doc)
            RYNotice(systemImage: "lock", title: "Файл ещё не добавлен",
                     text: "Сейчас в хранилище \(DocumentFormat.files(stored)). После загрузки будет \(stored + 1).")
        }
    }

    // MARK: Ошибка

    @ViewBuilder
    private func failedBody(title: String, detail: String) -> some View {
        RYNotice(systemImage: "icloud.slash", title: title, text: detail, tint: RYColor.dangerTint, ink: RYColor.danger)
            .accessibilityIdentifier("upload.error")
        if let doc {
            RYListGroup { fileRow(doc) }
            summaryGroup(doc)
            Text("Название, категория и доступ сохранены. Повторная загрузка не создаст дубликат.")
                .ryFont(.callout).foregroundStyle(RYColor.muted).padding(.top, 2)
            Text("В хранилище по-прежнему \(DocumentFormat.files(stored)). Этот документ ещё не добавлен.")
                .ryFont(.subhead).foregroundStyle(RYColor.muted)
        }
    }

    // MARK: Карточки

    private func fileRow(_ doc: DocumentRecord) -> some View {
        RYListRow(doc.title, subtitle: "\(doc.fileName) · \(DocumentFormat.kind(doc)) · \(DocumentFormat.size(doc.sizeBytes))",
                  minHeight: 56,
                  leading: { Image(systemName: "doc.text").font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24) },
                  trailing: { EmptyView() })
    }

    private func summaryGroup(_ doc: DocumentRecord) -> some View {
        let owner = members.first { $0.id == doc.ownerId }
        let draft = DocumentDraft(doc)
        return RYListGroup {
            RYListRow(doc.category.title, subtitle: "Категория",
                      leading: { Image(systemName: doc.category.systemImage).font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24) },
                      trailing: { EmptyView() })
            RYListDivider()
            DocumentPersonRow(member: owner, title: owner?.displayName ?? "Не указано", subtitle: "Кому принадлежит")
            RYListDivider()
            RYListRow(doc.access.title,
                      subtitle: DocumentFormView.accessTitle(draft, members: members, me: doc.authorId).replacingOccurrences(of: "Доступ: ", with: ""),
                      leading: { Image(systemName: "person.2").font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24) },
                      trailing: { EmptyView() })
        }
    }

    // MARK: Кнопки

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 8) {
            if case .failed = state {
                Button { session.uploads?.retry(documentId) } label: { Text("Повторить загрузку") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("upload.retry")
            } else {
                Button(action: onCancel) { Text("Отменить загрузку") }
                    .buttonStyle(.rySecondary).accessibilityIdentifier("upload.cancel")
                Text("При отмене файл не добавится в хранилище.").ryFont(.subhead).foregroundStyle(RYColor.muted)
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.bottom, 12).padding(.top, 8)
        .background(RYColor.background)
    }
}
