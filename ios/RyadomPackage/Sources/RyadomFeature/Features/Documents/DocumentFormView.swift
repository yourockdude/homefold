import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Новый документ и правка метаданных существующего — модальный лист. После «Загрузить» тот же лист
/// показывает прогресс загрузки (`DocumentUploadView`).
struct DocumentFormView: View {
    enum Mode: Hashable { case create, edit(UUID) }

    let mode: Mode
    @Binding var draft: DocumentDraft
    @Binding var pickedFile: ImportedFile?
    @Binding var pendingFilePicker: Bool
    let members: [MemberRecord]
    let familyName: String
    let isPremium: Bool
    let storedCount: Int
    var onClose: () -> Void
    var onScanDenied: () -> Void
    var onFinished: (UUID) -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @State private var submitted = false
    @State private var uploadingId: UUID?
    @State private var showSourceDialog = false
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var importError: String?
    @State private var limitMessage: String?
    @State private var paywallReason: PaywallReason?
    @State private var scanUnavailable = false
    @FocusState private var titleFocused: Bool

    private var isCreate: Bool { mode == .create }
    private var service: DocumentService? { session.documentService(context: context, isPremium: isPremium) }
    private var titleError: String? { submitted && draft.problem == .emptyTitle ? "Введите название документа." : nil }
    private var recipientsError: String? { submitted && draft.problem == .noRecipients ? "Выберите хотя бы одного участника." : nil }
    private var fileError: String? { submitted && isCreate && pickedFile == nil ? "Выберите файл или отсканируйте документ." : nil }

    var body: some View {
        Group {
            if let uploadingId {
                DocumentUploadView(documentId: uploadingId, members: members, storedCount: storedCount,
                                   onCancel: { session.uploads?.cancel(uploadingId); onClose() },
                                   onFinished: { onFinished(uploadingId) })
            } else {
                form
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RYColor.background)
        .presentationCornerRadius(RYRadius.sheet)
        .interactiveDismissDisabled(uploadingId != nil)
    }

    private var form: some View {
        RYSheetScaffold(title: isCreate ? "Новый документ" : "Редактировать документ",
                        confirmTitle: isCreate ? "Загрузить" : "Сохранить", confirmIdentifier: "document.submit",
                        onCancel: onClose, onConfirm: submit) {
            if isCreate { sourceSection }
            if let importError { RYStatusBanner(kind: .error, text: importError) }
            if let limitMessage {
                RYStatusBanner(kind: .error, text: limitMessage)
                Button { paywallReason = .documents } label: { Text("Подключить HomeFold Plus") }
                    .buttonStyle(.rySecondary).accessibilityIdentifier("document.upgrade")
            }
            titleField
            detailsGroup
            if draft.access == .selected { recipientChips }
            if let recipientsError { Text(recipientsError).ryFont(.subhead).foregroundStyle(RYColor.danger) }
            RYNotice(systemImage: "lock", title: Self.accessTitle(draft, members: members, me: session.userId),
                     text: "Файл хранится в зашифрованном виде. Права доступа проверяет сервер.")
        }
        .paywall(reason: $paywallReason)
        .confirmationDialog("Выбрать файл", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("Из «Файлов»") { showFileImporter = true }
            Button("Из «Фото»") { showPhotoPicker = true }
            Button("Отмена", role: .cancel) {}
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .jpeg, .png]) { result in handleFile(result) }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .task(id: photoItem) { await loadPhoto() }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerView(onFinish: { pages in showScanner = false; handleScan(pages) }, onCancel: { showScanner = false })
                .ignoresSafeArea()
        }
        .alert("Сканирование недоступно", isPresented: $scanUnavailable) {
            Button("Понятно", role: .cancel) {}
        } message: { Text("На этом устройстве нет сканера. Выберите файл из «Файлов» или «Фото».") }
        .onAppear {
            if pendingFilePicker { pendingFilePicker = false; showSourceDialog = true }
        }
    }

    // MARK: Части формы

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: RYSpacing.s) {
            HStack(spacing: 10) {
                Button(action: scanTapped) { Text("Сканировать") }
                    .buttonStyle(.rySecondary).accessibilityIdentifier("document.scan")
                Button { showSourceDialog = true } label: { Text("Выбрать файл") }
                    .buttonStyle(.rySecondary).accessibilityIdentifier("document.pickFile")
            }
            if let file = pickedFile {
                RYListGroup {
                    RYListRow(file.fileName, subtitle: "\(file.kind.shortTitle) · \(DocumentFormat.size(file.sizeBytes)) · выбран",
                              leading: {
                        Image(systemName: "doc.text").font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24)
                    }, trailing: { EmptyView() })
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Выбран: \(file.fileName) · \(file.kind.shortTitle) · \(DocumentFormat.size(file.sizeBytes))")
            }
            Text("PDF, JPG или PNG · до 25 МБ").ryFont(.subhead).foregroundStyle(fileError == nil ? RYColor.muted : RYColor.danger)
            if let fileError { Text(fileError).ryFont(.subhead).foregroundStyle(RYColor.danger) }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Название · обязательно")
            TextField("Например, полис ДМС", text: $draft.title)
                .focused($titleFocused).ryFont(.body).foregroundStyle(RYColor.ink)
                .ryField(isError: titleError != nil, isFocused: titleFocused)
                .accessibilityIdentifier("document.title")
            if let titleError { Text(titleError).ryFont(.subhead).foregroundStyle(RYColor.danger) }
        }
    }

    private var detailsGroup: some View {
        RYListGroup {
            RYValueRow(title: "Категория", systemImage: draft.category.systemImage) {
                Menu {
                    Picker("Категория", selection: $draft.category) {
                        ForEach(DocumentCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: { Text(draft.category.title) }
                    .accessibilityIdentifier("document.category")
            }
            RYListDivider()
            ownerRow
            RYListDivider()
            RYValueRow(title: "Номер") {
                TextField("Не указан", text: $draft.number).multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("document.number")
            }
            RYListDivider()
            expiryRow
            RYListDivider()
            RYValueRow(title: "Доступ", systemImage: "person.2") {
                Menu {
                    Picker("Доступ", selection: $draft.access) {
                        ForEach(DocumentAccess.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: { Text(draft.access.shortTitle) }
                    .accessibilityIdentifier("document.access")
            }
        }
    }

    private var ownerRow: some View {
        let owner = members.first { $0.id == draft.ownerId }
        return Menu {
            Picker("Кому принадлежит", selection: $draft.ownerId) {
                ForEach(members) { Text($0.displayName).tag(Optional($0.id)) }
            }
        } label: {
            HStack(spacing: 12) {
                if let owner { AvatarView(member: owner, diameter: 34) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Кому принадлежит").ryFont(.body).foregroundStyle(RYColor.ink)
                    Text(owner?.displayName ?? "Выберите участника").ryFont(.subhead).foregroundStyle(RYColor.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .medium)).foregroundStyle(RYColor.accent)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("document.owner")
    }

    private var expiryRow: some View {
        RYValueRow(title: "Срок действия", systemImage: "calendar") {
            if draft.expiresAt == nil {
                Button("Не указан") { draft.expiresAt = Calendar.current.date(byAdding: .year, value: 1, to: .now) }
                    .foregroundStyle(RYColor.muted).accessibilityIdentifier("document.expiryToggle")
            } else {
                HStack(spacing: 10) {
                    RYDateField(label: "Срок действия", value: draft.expiresAt.map { DocumentFormat.fullDate($0) } ?? "",
                                date: Binding(get: { draft.expiresAt ?? .now }, set: { draft.expiresAt = $0 }),
                                components: .date, identifier: "document.expiry", inline: true)
                    Button { draft.expiresAt = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(RYColor.muted)
                    }
                    .accessibilityLabel("Убрать срок действия").accessibilityIdentifier("document.expiryToggle")
                }
            }
        }
    }

    private var recipientChips: some View {
        let others = members.filter { $0.id != session.userId }
        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(others) { m in
                    let on = draft.selectedUserIds.contains(m.id)
                    Button {
                        if on { draft.selectedUserIds.remove(m.id) } else { draft.selectedUserIds.insert(m.id) }
                    } label: {
                        HStack(spacing: 6) {
                            AvatarView(member: m, diameter: 24)
                            Text(m.displayName).ryFont(.body).foregroundStyle(RYColor.ink)
                            if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(RYColor.accent) }
                        }
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(on ? RYColor.accentTint : RYColor.surface, in: Capsule())
                        .overlay(Capsule().stroke(on ? RYColor.accent : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m.displayName)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// «Доступ: Анна, Михаил и Соня»
    static func accessTitle(_ draft: DocumentDraft, members: [MemberRecord], me: UUID?) -> String {
        let names: [String]
        switch draft.access {
        case .family: names = members.map(\.displayName)
        case .authorOnly: return "Доступ: только вы"
        case .selected: names = members.filter { $0.id == me || draft.selectedUserIds.contains($0.id) }.map(\.displayName)
        }
        guard let last = names.last else { return "Доступ: только вы" }
        return "Доступ: " + (names.count > 1 ? names.dropLast().joined(separator: ", ") + " и " + last : last)
    }

    // MARK: Действия

    private func scanTapped() {
        importError = nil
        switch CameraAccess.current {
        case .unsupported: scanUnavailable = true
        case .denied: onScanDenied()
        case .authorized: showScanner = true
        case .notDetermined:
            Task {
                if await CameraAccess.request() { showScanner = true } else { onScanDenied() }
            }
        }
    }

    private func handleScan(_ pages: [UIImage]) {
        apply { try DocumentImport.scan(pages: pages, name: "Скан " + RussianDate.dayMonth(.now)) }
    }

    private func handleFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): apply { try DocumentImport.file(at: url) }
        case .failure: importError = DocumentImportError.unreadable.errorDescription
        }
    }

    private func loadPhoto() async {
        guard let item = photoItem else { return }
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            importError = DocumentImportError.unreadable.errorDescription
            return
        }
        apply { try DocumentImport.photo(data: data, suggestedName: "Фото " + RussianDate.dayMonth(.now) + ".jpg") }
    }

    private func apply(_ make: () throws -> ImportedFile) {
        do {
            let file = try make()
            pickedFile = file
            importError = nil
            if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = file.suggestedTitle }
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? "Не удалось добавить файл."
        }
    }

    private func submit() {
        submitted = true
        limitMessage = nil
        guard draft.problem == nil else { return }
        switch mode {
        case .create:
            guard let file = pickedFile, let service else { return }
            do {
                let doc = try service.add(draft, file: file)
                pickedFile = nil
                if let uploads = session.uploads {
                    uploads.start(doc.id)
                    uploadingId = doc.id
                } else {
                    // Нет сервера или входа: файл сохранён на устройстве, отправится при синхронизации.
                    onFinished(doc.id)
                }
            } catch DocumentServiceError.limitReached(let reason) {
                limitMessage = reason == .fileCount
                    ? "Бесплатный тариф вмещает до 10 файлов. Удалите ненужный документ или подключите HomeFold Plus."
                    : "Бесплатный тариф вмещает до 100 МБ. Удалите ненужный документ или подключите HomeFold Plus."
            } catch {
                importError = "Не удалось сохранить документ."
            }
        case .edit(let id):
            guard let doc = (try? context.fetch(FetchDescriptor<DocumentRecord>(predicate: #Predicate { $0.id == id })))?.first else { return }
            do { try service?.update(doc, with: draft); onClose() } catch { importError = "Менять документ может только его автор." }
        }
    }
}

extension DocumentAccess {
    /// Короткая подпись для значения в строке: «Всей семье».
    var shortTitle: String {
        switch self {
        case .authorOnly: "Только автор"
        case .selected: "Выбранным"
        case .family: "Всей семье"
        }
    }
}
