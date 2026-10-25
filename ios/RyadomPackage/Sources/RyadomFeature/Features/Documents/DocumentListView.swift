import SwiftUI
import SwiftData

/// «Все файлы» и файлы одной категории.
struct DocumentListView: View {
    let members: [MemberRecord]
    @Binding var path: [DocumentRoute]

    @Query(filter: #Predicate<DocumentRecord> { $0.deletedAt == nil }, sort: \DocumentRecord.createdAt, order: .reverse)
    private var docs: [DocumentRecord]
    @State private var category: DocumentCategory?

    init(category: DocumentCategory?, members: [MemberRecord], path: Binding<[DocumentRoute]>) {
        self.members = members
        self._path = path
        self._category = State(initialValue: category)
    }

    private var shown: [DocumentRecord] { category == nil ? docs : docs.filter { $0.category == category } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: RYSpacing.s) {
                Button { if !path.isEmpty { path.removeLast() } } label: {
                    Image(systemName: "arrow.left").font(.system(size: 18)).foregroundStyle(RYColor.ink)
                }
                .accessibilityLabel("Назад")
                Text(category?.title ?? "Все файлы").ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(DocumentFormat.files(shown.count)).ryFont(.caption).foregroundStyle(RYColor.muted)
            }
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.m)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip("Все", selected: category == nil) { category = nil }
                    ForEach(DocumentCategory.allCases, id: \.self) { c in chip(c.title, selected: category == c) { category = c } }
                }
                .padding(.horizontal, RYSpacing.screen)
            }
            .scrollIndicators(.hidden)
            .padding(.bottom, RYSpacing.s)

            ScrollView {
                if shown.isEmpty {
                    RYEmptyState(systemImage: category?.systemImage ?? "folder", title: "Здесь пока пусто",
                                 message: "В этой категории нет документов. Добавьте первый с помощью кнопки «+» на экране документов.")
                        .padding(.top, RYSpacing.l)
                } else {
                    VStack(spacing: 0) {
                        ForEach(shown) { doc in DocumentRow(doc: doc) { path.append(.detail(doc.id, added: false)) } }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
                    .padding(.horizontal, RYSpacing.screen)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ryFont(.caption).fontWeight(.medium).foregroundStyle(selected ? .white : RYColor.muted)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(selected ? RYColor.accent : RYColor.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
