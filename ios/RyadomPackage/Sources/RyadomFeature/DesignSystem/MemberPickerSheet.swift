import SwiftUI

/// Лист выбора участника семьи («Кто возьмёт дело?»).
struct MemberPickerSheet: View {
    let title: String
    let subtitle: String
    let members: [MemberRecord]
    let currentUserId: UUID?
    var noneTitle: String?
    @Binding var selection: UUID?
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var draft: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: RYSpacing.m) {
            HStack {
                Text(title).ryFont(.heading).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).foregroundStyle(RYColor.accent)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Закрыть")
            }
            Text(subtitle).ryFont(.body).foregroundStyle(RYColor.muted)
            VStack(spacing: 0) {
                if let noneTitle { row(id: nil, name: noneTitle, caption: "Показать дела всех", tone: nil) }
                ForEach(members) { m in
                    row(id: m.id, name: m.displayName,
                        caption: m.id == currentUserId ? "Вы" : "Участник семьи", tone: m)
                }
            }
            .padding(.horizontal, 14)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            Button("Готово") {
                selection = draft
                onDone()
                dismiss()
            }
            .buttonStyle(.ryPrimary)
            .accessibilityIdentifier("picker.done")
            Button("Отмена") { dismiss() }
                .ryFont(.bodyMedium).foregroundStyle(RYColor.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, RYSpacing.screen)
        .padding(.top, RYSpacing.l)
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RYColor.background)
        .onAppear { draft = selection }
    }

    private func row(id: UUID?, name: String, caption: String, tone: MemberRecord?) -> some View {
        Button { draft = id } label: {
            HStack(spacing: RYSpacing.s) {
                if let tone {
                    AvatarView(name: tone.displayName, tone: tone.tone, diameter: 36)
                } else {
                    Image(systemName: "person.2").font(.system(size: 15, weight: .light)).foregroundStyle(RYColor.accent)
                        .frame(width: 36, height: 36).background(RYColor.accentTint, in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                    Text(draft == id ? (id == currentUserId && id != nil ? "Вы · выбрана" : "Выбрана") : caption)
                        .ryFont(.micro).foregroundStyle(RYColor.muted)
                }
                Spacer()
                ZStack {
                    Circle().stroke(draft == id ? RYColor.accent : RYColor.checkBorder, lineWidth: 1.3)
                    if draft == id {
                        Circle().fill(RYColor.accent)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(draft == id ? .isSelected : [])
    }
}
