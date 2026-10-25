import SwiftUI
import SwiftData
import PDFKit

/// Просмотр PDF и изображений. Открывается только после снятия блокировки Face ID.
struct DocumentViewerView: View {
    let documentId: UUID
    @Binding var path: [DocumentRoute]

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Query private var matches: [DocumentRecord]

    init(documentId: UUID, path: Binding<[DocumentRoute]>) {
        self.documentId = documentId
        self._path = path
        _matches = Query(filter: #Predicate<DocumentRecord> { $0.id == documentId })
    }

    private var doc: DocumentRecord? { matches.first }
    private var fileURL: URL? {
        doc.flatMap { session.documentService(context: context, isPremium: false)?.fileURL(for: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RYSpacing.s) {
                RYBackButton("Документ") { if !path.isEmpty { path.removeLast() } }
                Spacer()
                Text(doc?.title ?? "").ryFont(.callout).foregroundStyle(RYColor.muted).lineLimit(1)
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 10)

            Group {
                if !session.documentsLock.isContentVisible {
                    RYEmptyState(illustration: .lock, title: "Документ закрыт", message: "Разблокируйте документы, чтобы продолжить.",
                                 actionTitle: "Разблокировать") { Task { await session.documentsLock.unlock() } }
                } else if let url = fileURL, let doc, let kind = DocumentFileKind(mimeType: doc.mimeType) {
                    if kind == .pdf { PDFKitView(url: url).accessibilityLabel("Содержимое документа") }
                    else { ZoomableImage(url: url) }
                } else {
                    RYEmptyState(systemImage: "doc", title: "Файла нет на устройстве", message: "Вернитесь назад и откройте документ снова: он скачается из хранилища.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .privacySensitive()
        .accessibilityIdentifier("document.viewer")
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

struct ZoomableImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().scaleEffect(scale)
                    .frame(maxWidth: .infinity)
                    .gesture(MagnifyGesture().onChanged { scale = max(1, min(5, $0.magnification)) }.onEnded { _ in })
                    .accessibilityLabel("Изображение документа")
            }
        }
        .task { image = await Task.detached { DocumentThumbnail.downsample(url, maxPixel: 2400) }.value }
    }
}
