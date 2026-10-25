import SwiftUI

/// Лист выбора участника: «Кто возьмёт дело?» и «Чьи дела показать?».
struct TaskMemberPickerSheet: View {
    let navTitle: String
    let heading: String
    let subtitle: String
    let members: [MemberRecord]
    let currentUserId: UUID?
    var noneTitle: String?
    @Binding var selection: UUID?
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var draft: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text(navTitle).ryFont(.headline).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                HStack {
                    Button("Отмена") { dismiss() }.ryFont(.body).foregroundStyle(RYColor.accent)
                    Spacer()
                    Button("Готово") { selection = draft; onDone(); dismiss() }
                        .ryFont(.headline).foregroundStyle(RYColor.accent).accessibilityIdentifier("picker.done")
                }
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, 22).padding(.bottom, 18)

            Text(heading).ryFont(.heading).foregroundStyle(RYColor.ink)
                .padding(.horizontal, RYSpacing.screen).accessibilityAddTraits(.isHeader)
            Text(subtitle).ryFont(.callout).foregroundStyle(RYColor.muted)
                .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 14)

            RYListGroup {
                if let noneTitle {
                    row(id: nil, name: noneTitle, caption: "Показать дела всех", member: nil)
                    RYListDivider(inset: 48)
                }
                ForEach(Array(members.enumerated()), id: \.element.id) { index, m in
                    row(id: m.id, name: m.displayName, caption: m.id == currentUserId ? "Вы" : "Участник семьи", member: m)
                    if index < members.count - 1 { RYListDivider(inset: 48) }
                }
            }
            .padding(.horizontal, RYSpacing.screen)
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RYColor.background)
        .presentationCornerRadius(RYRadius.sheet)
        .onAppear { draft = selection }
    }

    private func row(id: UUID?, name: String, caption: String, member: MemberRecord?) -> some View {
        Button { draft = id } label: {
            HStack(spacing: 12) {
                if let member {
                    AvatarView(member: member, diameter: 36)
                } else {
                    Image(systemName: "person.2").font(.system(size: 15, weight: .light)).foregroundStyle(RYColor.accent)
                        .frame(width: 36, height: 36).background(RYColor.accentTint, in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).ryFont(.body).foregroundStyle(RYColor.ink)
                    Text(draft == id ? (id != nil && id == currentUserId ? "Вы · выбрана" : "Выбрана") : caption).ryFont(.subhead).foregroundStyle(RYColor.muted)
                }
                Spacer()
                if draft == id { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(RYColor.accent) }
            }
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(draft == id ? .isSelected : [])
    }
}
