import SwiftUI

/// Нет доступа к камере: объясняет, как включить, и предлагает выбрать файл вместо скана.
struct CameraDeniedView: View {
    @Binding var draft: DocumentDraft
    @Binding var pickedFile: ImportedFile?
    let storedCount: Int
    let members: [MemberRecord]
    var onPickFile: () -> Void
    @Binding var path: [DocumentRoute]

    @Environment(\.openURL) private var openURL

    private var ownerLine: String {
        guard let owner = members.first(where: { $0.id == draft.ownerId }) else { return "" }
        return "Принадлежит \(RussianNames.dative(owner.displayName)) · "
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RYBackButton("Документы") { if !path.isEmpty { path.removeLast() } }
                Spacer()
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 10)

            ScrollView {
                VStack(spacing: RYSpacing.s) {
                    Text("Сканирование").ryFont(.title).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    RYIllustration(.camera, height: 150).padding(.top, 6)
                    Text("Нужен доступ к камере").ryFont(.heading).foregroundStyle(RYColor.ink)
                        .multilineTextAlignment(.center)
                    Text("Разрешите приложению «рядом» использовать камеру в настройках телефона. Тогда вы сможете сканировать документы.")
                        .ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
                    RYNotice(systemImage: "checkmark.shield", title: "Настройки → рядом → Камера",
                             text: "Включите доступ и вернитесь в приложение. Камера используется только для сканирования.")
                    RYListGroup {
                        RYListRow(draft.title.isEmpty ? "Без названия" : draft.title,
                                  subtitle: "Ваши данные сохранены · \(draft.category.title)", minHeight: 56,
                                  leading: { Image(systemName: "doc.text").font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24) },
                                  trailing: { EmptyView() })
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ownerLine)\(CameraDeniedView.accessLine(draft))")
                        Text("\(pickedFile == nil ? "Файл ещё не выбран" : "Файл выбран") · в хранилище \(DocumentFormat.files(storedCount))")
                    }
                    .ryFont(.subhead).foregroundStyle(RYColor.muted).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Text("Открыть настройки") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("camera.openSettings")
                Button(action: onPickFile) { Text("Выбрать файл вместо скана") }
                    .buttonStyle(.rySecondary).accessibilityIdentifier("camera.pickFile")
            }
            .padding(.horizontal, RYSpacing.screen).padding(.bottom, 4).padding(.top, 8)
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
}
