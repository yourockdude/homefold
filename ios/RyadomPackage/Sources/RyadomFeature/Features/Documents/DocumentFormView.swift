import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Новый документ и правка метаданных существующего.
struct DocumentFormView: View {
    enum Mode: Hashable { case create, edit(UUID) }

    let mode: Mode
    @Binding var draft: DocumentDraft
    @Binding var pickedFile: ImportedFile?
    @Binding var pendingFilePicker: Bool
    let members: [MemberRecord]
    let familyName: String
    let isPremium: Bool
    @Binding var path: [DocumentRoute]

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @State private var submitted = false
    @State private var showSourceDialog = false
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var importError: String?
    @State private var limitMessage: String?
    @State private var scanUnavailable = false
    @FocusState private var titleFocused: Bool

    private var isCreate: Bool { mode == .create }
    private var service: DocumentService? { session.documentService(context: context, isPremium: isPremium) }
    private var titleError: String? { submitted && draft.problem == .emptyTitle ? "Введите название документа." : nil }
    private var recipientsError: String? { submitted && draft.problem == .noRecipients ? "Выберите хотя бы одного участника." : nil }
    private var fileError: String? { submitted && isCreate && pickedFile == nil ? "Выберите файл или отсканируйте документ." : nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.s) {
                    if isCreate { sourceSection }
                    if let importError { RYStatusBanner(kind: .error, text: importError) }
                    if let limitMessage { RYStatusBanner(kind: .error, text: limitMessage) }
                    titleField
                    categoryField
                    ownerField
                    numberField
                    expiryField
                    accessField
                    accessNotice
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.bottom, RYSpacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: submit) {
                Label(isCreate ? "Загрузить документ" : "Сохранить", systemImage: isCreate ? "square.and.arrow.up" : "checkmark")
            }
            .buttonStyle(.ryPrimary)
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
            .background(RYColor.background)
            .accessibilityIdentifier("document.submit")
        }
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

    private var topBar: some View {
        HStack(spacing: RYSpacing.s) {
            Button(action: close) { Image(systemName: "arrow.left").font(.system(size: 18)).foregroundStyle(RYColor.ink) }
                .accessibilityLabel("Назад")
            Text(isCreate ? "Новый документ" : "Редактировать документ").ryFont(.section).foregroundStyle(RYColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(RYColor.ink)
                    .frame(width: 40, height: 40).background(RYColor.surface, in: Circle())
            }
            .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.m)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            RYFieldLabel("Откуда добавить")
            HStack(spacing: RYSpacing.s) {
                sourceTile(title: "Сканировать", systemImage: "camera", selected: false, action: scanTapped)
                    .accessibilityIdentifier("document.scan")
                sourceTile(title: "Выбрать файл", systemImage: "doc.text", selected: pickedFile != nil) { showSourceDialog = true }
                    .accessibilityIdentifier("document.pickFile")
            }
            if let file = pickedFile {
                Text("Выбран: \(file.fileName) · \(file.kind.shortTitle) · \(DocumentFormat.size(file.sizeBytes))")
                    .ryFont(.micro).foregroundStyle(RYColor.muted)
            } else {
                Text("PDF, JPG и PNG · до 25 МБ").ryFont(.micro).foregroundStyle(fileError == nil ? RYColor.muted : RYColor.danger)
            }
            if let fileError { Text(fileError).ryFont(.caption).foregroundStyle(RYColor.danger) }
        }
    }

    private func sourceTile(title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 17, weight: .light))
                Text(title).ryFont(.caption).fontWeight(.medium)
            }
            .foregroundStyle(selected ? RYColor.accent : RYColor.ink)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(selected ? RYColor.accentTint : RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            .overlay(RoundedRectangle(cornerRadius: RYRadius.card).stroke(selected ? RYColor.accent : RYColor.border, lineWidth: selected ? 1.3 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Название" + (titleError != nil ? " *" : ""))
            TextField("Например, полис ДМС", text: $draft.title)
                .focused($titleFocused).ryFont(.body).foregroundStyle(RYColor.ink)
                .ryField(isError: titleError != nil, isFocused: titleFocused)
                .accessibilityIdentifier("document.title")
            if let titleError { Text(titleError).ryFont(.caption).foregroundStyle(RYColor.danger) }
        }
    }

    private var categoryField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Категория")
            Menu {
                Picker("Категория", selection: $draft.category) {
                    ForEach(DocumentCategory.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: { RYSelectLabel(value: draft.category.title) }
                .accessibilityIdentifier("document.category")
        }
    }

    private var ownerField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Кому принадлежит")
            Menu {
                Picker("Кому принадлежит", selection: $draft.ownerId) {
                    ForEach(members) { Text($0.displayName).tag(Optional($0.id)) }
                }
            } label: { RYSelectLabel(value: members.first { $0.id == draft.ownerId }?.displayName ?? "Выберите участника") }
                .accessibilityIdentifier("document.owner")
        }
    }

    private var numberField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Номер · необязательно")
            TextField("Номер документа", text: $draft.number).ryFont(.body).foregroundStyle(RYColor.ink).ryField()
                .accessibilityIdentifier("document.number")
        }
    }

    private var expiryField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RYFieldLabel("Срок действия · необязательно")
                Spacer()
                Button(draft.expiresAt == nil ? "Указать" : "Убрать") {
                    draft.expiresAt = draft.expiresAt == nil ? Calendar.current.date(byAdding: .year, value: 1, to: .now) : nil
                }
                .ryFont(.caption).foregroundStyle(RYColor.accent)
                .accessibilityIdentifier("document.expiryToggle")
            }
            if draft.expiresAt != nil {
                RYDateField(label: "Срок действия", value: draft.expiresAt.map { DocumentFormat.fullDate($0) } ?? "",
                            date: Binding(get: { draft.expiresAt ?? .now }, set: { draft.expiresAt = $0 }),
                            components: .date, identifier: "document.expiry")
            } else {
                RYSelectLabel(value: "Не указан", systemImage: "calendar")
            }
        }
    }

    private var accessField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Доступ")
            Menu {
                Picker("Доступ", selection: $draft.access) {
                    ForEach(DocumentAccess.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } label: { RYSelectLabel(value: draft.access.title) }
                .accessibilityIdentifier("document.access")
            if draft.access == .selected { recipientChips }
            if let recipientsError { Text(recipientsError).ryFont(.caption).foregroundStyle(RYColor.danger) }
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
                            AvatarView(name: m.displayName, tone: m.tone, diameter: 22)
                            Text(m.displayName).ryFont(.body).foregroundStyle(RYColor.ink)
                            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(RYColor.accent) }
                        }
                        .padding(.horizontal, 10).frame(minHeight: 40)
                        .background(on ? RYColor.accentTint : RYColor.surface, in: Capsule())
                        .overlay(Capsule().stroke(on ? RYColor.accent : RYColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m.displayName)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var accessNotice: some View {
        DocumentNotice(systemImage: "lock", title: Self.accessTitle(draft, members: members, me: session.userId),
                       text: "Файл хранится в зашифрованном виде. Права доступа проверяет сервер.")
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
        case .denied: path.append(.cameraDenied)
        case .authorized: showScanner = true
        case .notDetermined:
            Task {
                if await CameraAccess.request() { showScanner = true } else { path.append(.cameraDenied) }
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
                    path = Array(path.dropLast()) + [.upload(doc.id)]
                } else {
                    // Нет сервера или входа: файл сохранён на устройстве, отправится при синхронизации.
                    path = Array(path.dropLast()) + [.detail(doc.id, added: true)]
                }
            } catch DocumentServiceError.limitReached(let reason) {
                limitMessage = reason == .fileCount
                    ? "Бесплатный тариф вмещает до 10 файлов. Удалите ненужный документ или подключите «рядом Плюс»."
                    : "Бесплатный тариф вмещает до 100 МБ. Удалите ненужный документ или подключите «рядом Плюс»."
            } catch {
                importError = "Не удалось сохранить документ."
            }
        case .edit(let id):
            guard let doc = (try? context.fetch(FetchDescriptor<DocumentRecord>(predicate: #Predicate { $0.id == id })))?.first else { return }
            do { try service?.update(doc, with: draft); close() } catch { importError = "Менять документ может только его автор." }
        }
    }

    private func close() { if !path.isEmpty { path.removeLast() } }
}
