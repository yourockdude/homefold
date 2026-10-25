import SwiftUI

/// Карточка дела в списке дня.
struct TaskCard: View {
    let task: TaskOccurrenceRecord
    let assignee: MemberRecord?
    let isHighlighted: Bool
    let isOverdue: Bool
    var onToggle: () -> Void
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                RYCheckbox(isOn: task.isCompleted).padding(.top, 2).frame(minWidth: 30, minHeight: 30, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Вернуть в работу: \(task.title)" : "Отметить выполненным: \(task.title)")
            .accessibilityIdentifier("task.check.\(task.title)")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 11) {
                    Text(task.title).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                        .font(.system(size: 14)).multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        if task.hasTime {
                            Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(timeColor)
                            Text(RussianDate.time(task.dueAt)).ryFont(.micro).foregroundStyle(timeColor)
                        } else {
                            Image(systemName: "sun.max").font(.system(size: 11)).foregroundStyle(RYColor.muted)
                            Text("В течение дня").ryFont(.micro).foregroundStyle(RYColor.muted)
                        }
                        if !task.tag.isEmpty {
                            Text("· \(task.tag)").ryFont(.micro).foregroundStyle(RYColor.muted)
                        }
                        Spacer(minLength: 4)
                        if task.syncStatus == .pending {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9))
                                .foregroundStyle(RYColor.muted).accessibilityLabel("Ожидает синхронизации")
                        }
                        if let assignee { AvatarView(name: assignee.displayName, tone: assignee.tone, diameter: 25) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открыть дело")
        }
        .padding(14)
        .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
        .overlay(RoundedRectangle(cornerRadius: RYRadius.card)
            .stroke(isOverdue ? RYColor.danger.opacity(0.35) : (isHighlighted ? Color(hex: 0xC3D4C3) : RYColor.border), lineWidth: 1))
    }

    private var timeColor: Color {
        if isOverdue { RYColor.danger } else if isHighlighted { RYColor.peachInk } else { RYColor.muted }
    }
}
