import SwiftUI

/// Нет доступа к камере: объясняет, как включить, и предлагает выбрать файл вместо скана.
struct CameraDeniedView: View {
    @Binding var draft: DocumentDraft
    let pickedFile: ImportedFile?
    let storedCount: Int
    let members: [MemberRecord]
    @Binding var pendingFilePicker: Bool
    @Binding var path: [DocumentRoute]

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RYSpacing.s) {
                Button(action: close) { Image(systemName: "arrow.left").font(.system(size: 18)).foregroundStyle(RYColor.ink) }
                    .accessibilityLabel("Назад")
                Text("Сканировать документ").ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(RYColor.ink)
                        .frame(width: 40, height: 40).background(RYColor.surface, in: Circle())
                }
                .accessibilityLabel("Закрыть")
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.m)

            ScrollView {
                VStack(spacing: RYSpacing.m) {
                    Image(systemName: "camera").font(.system(size: 26, weight: .light)).foregroundStyle(RYColor.accent)
                        .overlay { Rectangle().fill(RYColor.accent).frame(width: 34, height: 1.5).rotationEffect(.degrees(-45)) }
                        .frame(width: 64, height: 64).background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityHidden(true)
                    Text("Нужен доступ к камере").font(.system(size: 26, weight: .semibold)).foregroundStyle(RYColor.ink)
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                    Text("Разрешите приложению «рядом» использовать камеру в настройках телефона. Тогда вы сможете сканировать документы.")
                        .ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
                    DocumentNotice(systemImage: "shield", title: "Настройки → рядом → Камера",
                                   text: "Включите доступ и вернитесь в приложение. Камера используется только для сканирования.")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ваши данные сохранены").ryFont(.micro).foregroundStyle(RYColor.muted)
                        RYFieldLabel("Название документа")
                        Text(draft.title.isEmpty ? "Без названия" : draft.title).ryFont(.body).foregroundStyle(RYColor.ink).ryField()
                        Text("\(draft.category.title) · \(Self.accessLine(draft)) · \(pickedFile == nil ? "Файл ещё не выбран" : "Файл выбран") · в хранилище \(DocumentFormat.files(storedCount))")
                            .ryFont(.micro).foregroundStyle(RYColor.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, RYSpacing.screen)
            }
            .scrollIndicators(.hidden)
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: RYSpacing.xs) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Label("Открыть настройки", systemImage: "gearshape") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("camera.openSettings")
                Button {
                    pendingFilePicker = true
                    close()
                } label: { Label("Выбрать файл вместо скана", systemImage: "doc.text") }
                    .buttonStyle(.rySecondary).accessibilityIdentifier("camera.pickFile")
            }
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
            .background(RYColor.background)
        }
    }

    static func accessLine(_ draft: DocumentDraft) -> String {
        switch draft.access {
        case .family: "доступ всей семье"
        case .authorOnly: "доступ только вам"
        case .selected: "доступ выбранным участникам"
        }
    }

    private func close() { if !path.isEmpty { path.removeLast() } }
}
