import SwiftUI
import PDFKit

enum DocumentRoute: Hashable {
    case add
    case edit(UUID)
    case cameraDenied
    case upload(UUID)
    case detail(UUID, added: Bool)
    case list(DocumentCategory?)
    case viewer(UUID)
}

struct RYSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .light)).foregroundStyle(RYColor.muted)
            TextField("Найти документ", text: $text)
                .focused($focused)
                .ryFont(.body).foregroundStyle(RYColor.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("documents.search")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(RYColor.muted)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(text.isEmpty && !focused ? Color(hex: 0xECEFE6) : RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
        .overlay(RoundedRectangle(cornerRadius: RYRadius.card)
            .stroke(focused || !text.isEmpty ? RYColor.accent : .clear, lineWidth: 1.3))
    }
}

/// Значок категории: пастельный квадрат с тонкой иконкой.
struct DocumentIcon: View {
    let category: DocumentCategory
    var width: CGFloat = 42
    var height: CGFloat = 46

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: width * 0.45, weight: .light))
            .foregroundStyle(category.tone.ink)
            .frame(width: width, height: height)
            .background(category.tone.background, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct DocumentRow: View {
    let doc: DocumentRecord
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                DocumentIcon(category: doc.category)
                VStack(alignment: .leading, spacing: 6) {
                    Text(doc.title).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink).multilineTextAlignment(.leading)
                    Text(DocumentFormat.subtitle(doc)).ryFont(.micro).foregroundStyle(RYColor.muted)
                    if doc.uploadState != .synced { statusLabel }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(RYColor.muted)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("document.row.\(doc.title)")
    }

    @ViewBuilder private var statusLabel: some View {
        switch doc.uploadState {
        case .failed:
            Label("Не отправлен", systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(RYColor.danger)
        default:
            Label("Ожидает синхронизации", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 10)).foregroundStyle(RYColor.muted)
        }
    }
}

struct CategoryCard: View {
    let category: DocumentCategory
    let count: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: category.systemImage).font(.system(size: 14, weight: .light))
                        .foregroundStyle(category.tone.ink).frame(width: 30, height: 30)
                        .background(category.tone.background, in: RoundedRectangle(cornerRadius: 9))
                    Text(category.title).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                    Spacer(minLength: 0)
                }
                Text(DocumentFormat.documents(count)).ryFont(.micro).foregroundStyle(RYColor.muted)
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

/// Информационная плашка с иконкой: защита, доступ.
struct DocumentNotice: View {
    let systemImage: String
    var title: String?
    let text: String
    var tint: Color = RYColor.accentTint
    var ink: Color = RYColor.accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 15, weight: .light)).foregroundStyle(ink).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if let title { Text(title).ryFont(.caption).fontWeight(.semibold).foregroundStyle(ink) }
                Text(text).ryFont(.micro).foregroundStyle(ink.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: RYRadius.card))
        .accessibilityElement(children: .combine)
    }
}

/// Иллюстрация пустого хранилища: папка с документом и замком.
struct DocumentsIllustration: View {
    var body: some View {
        ZStack {
            Circle().fill(RYColor.accentTint).frame(width: 190, height: 190)
            RoundedRectangle(cornerRadius: 14).fill(RYColor.accent.opacity(0.35)).frame(width: 150, height: 96).offset(x: -4, y: 20)
            RoundedRectangle(cornerRadius: 10).fill(.white).frame(width: 86, height: 100)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "doc.badge.checkmark").font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent)
                        Capsule().fill(RYColor.accentTint).frame(width: 56, height: 5)
                        Capsule().fill(RYColor.accentTint).frame(width: 40, height: 5)
                    }
                    .padding(12)
                }
                .rotationEffect(.degrees(6)).offset(x: 6, y: -14)
            RoundedRectangle(cornerRadius: 14).fill(RYColor.accent).frame(width: 150, height: 78).offset(y: 40)
            Image(systemName: "lock").font(.system(size: 17, weight: .light)).foregroundStyle(RYColor.peachInk)
                .frame(width: 44, height: 44).background(.white, in: Circle())
                .overlay(Circle().stroke(RYColor.peach, lineWidth: 3)).offset(x: 66, y: 46)
            Circle().fill(RYColor.accent.opacity(0.4)).frame(width: 9, height: 9).offset(x: -90, y: -50)
            Circle().fill(RYColor.peachInk.opacity(0.6)).frame(width: 6, height: 6).offset(x: 88, y: -34)
        }
        .frame(height: 200)
        .accessibilityHidden(true)
    }
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
