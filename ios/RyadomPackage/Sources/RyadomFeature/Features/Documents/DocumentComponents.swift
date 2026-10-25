import SwiftUI
import PDFKit

enum DocumentRoute: Hashable {
    case cameraDenied
    case detail(UUID, added: Bool)
    case list(DocumentCategory?)
    case viewer(UUID)
}

/// Модальные листы формы документа.
enum DocumentSheet: Identifiable, Hashable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let id): "edit-\(id.uuidString)"
        }
    }
}

/// Поле поиска: серая подложка r13 высотой 44, значок лупы, кнопка очистки.
struct RYSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .regular)).foregroundStyle(RYColor.muted)
            TextField("Найти документ", text: $text)
                .focused($focused)
                .ryFont(.body).foregroundStyle(RYColor.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("documents.search")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(RYColor.muted)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RYColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 13))
    }
}

/// Значок категории: тонкий контур акцентным цветом, без цветной плашки.
struct DocumentIcon: View {
    let category: DocumentCategory
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: size, weight: .light))
            .foregroundStyle(RYColor.accent)
            .frame(width: size + 4, height: size + 4)
            .accessibilityHidden(true)
    }
}

/// Строка документа. Размещается внутри `RYListGroup`, разделители ставит вызывающий код.
struct DocumentRow: View {
    let doc: DocumentRecord
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RYListRow(doc.title, subtitle: DocumentFormat.subtitle(doc),
                      leading: { DocumentIcon(category: doc.category) },
                      trailing: {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("›").ryFont(.callout).foregroundStyle(RYColor.accent)
                    if doc.uploadState != .synced { statusIcon }
                }
            })
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("document.row.\(doc.title)")
    }

    @ViewBuilder private var statusIcon: some View {
        if doc.uploadState == .failed {
            Image(systemName: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(RYColor.danger)
                .accessibilityLabel("Не отправлен")
        } else {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)).foregroundStyle(RYColor.muted)
                .accessibilityLabel("Ожидает синхронизации")
        }
    }
}

/// Список документов в одной карточке с разделителями.
struct DocumentList: View {
    let docs: [DocumentRecord]
    var onOpen: (DocumentRecord) -> Void

    var body: some View {
        RYListGroup {
            ForEach(Array(docs.enumerated()), id: \.element.id) { index, doc in
                DocumentRow(doc: doc) { onOpen(doc) }
                if index < docs.count - 1 { RYListDivider() }
            }
        }
    }
}

struct CategoryCard: View {
    let category: DocumentCategory
    let count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    DocumentIcon(category: category)
                    Text(category.title).ryFont(.bodyMedium).foregroundStyle(RYColor.ink)
                    Spacer(minLength: 0)
                }
                Text(DocumentFormat.documents(count)).ryFont(.subhead).foregroundStyle(RYColor.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("category.\(category.rawValue)")
    }
}

/// Иллюстрация пустого хранилища: синяя папка с документами.
struct DocumentsIllustration: View {
    var body: some View { RYIllustration(.folder, height: 210) }
}

/// Миниатюра первой страницы PDF или изображения.
enum DocumentThumbnail {
    static func render(url: URL, kind: DocumentFileKind, maxWidth: CGFloat) -> UIImage? {
        switch kind {
        case .pdf:
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let box = page.bounds(for: .mediaBox)
            let scale = maxWidth * 2 / max(box.width, 1)
            return page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
        case .jpeg, .png:
            return downsample(url, maxPixel: maxWidth * 2)
        }
    }

    static func downsample(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceShouldCacheImmediately: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}

/// Стандартное системное меню «Поделиться».
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareItem: Identifiable { let id = UUID(); let url: URL }

/// Строка группы с аватаром участника (владелец, автор).
struct DocumentPersonRow: View {
    let member: MemberRecord?
    let title: String
    let subtitle: String

    var body: some View {
        RYListRow(title, subtitle: subtitle, leading: {
            if let member { AvatarView(name: member.displayName, tone: member.tone, diameter: 32) }
            else { Circle().fill(RYColor.accentTint).frame(width: 32, height: 32) }
        }, trailing: { EmptyView() })
        .accessibilityElement(children: .combine)
    }
}

/// Строка «Доступ: …» с замком под группой метаданных.
struct DocumentAccessLine: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock").font(.system(size: 14, weight: .light)).foregroundStyle(RYColor.accent).padding(.top, 1)
            Text(text).ryFont(.subhead).foregroundStyle(RYColor.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}
