import SwiftUI

/// Диалог подтверждения в стиле системного алерта: 300 pt, r28, кнопки-строки с тонкими разделителями.
struct RYConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    var extraTitle: String?
    var onExtra: (() -> Void)?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            RYColor.scrim
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Text(title).ryFont(.headline).foregroundStyle(RYColor.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(message).ryFont(.subhead).foregroundStyle(RYColor.ink)
                }
                .multilineTextAlignment(.center)
                .padding(22)
                row(confirmTitle, color: RYColor.danger, weight: .regular, id: "dialog.confirm", action: onConfirm)
                if let extraTitle, let onExtra { row(extraTitle, color: RYColor.danger, weight: .regular, id: "dialog.extra", action: onExtra) }
                row("Отмена", color: RYColor.accent, weight: .semibold, id: "dialog.cancel", action: onCancel)
            }
            .frame(width: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: RYRadius.sheet))
            .background(Color(hex: 0xF9F9F9, opacity: 0.95), in: RoundedRectangle(cornerRadius: RYRadius.sheet))
            .clipShape(RoundedRectangle(cornerRadius: RYRadius.sheet))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private func row(_ title: String, color: Color, weight: Font.Weight, id: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(RYColor.separator).frame(height: 0.5)
            Button(action: action) {
                Text(title).font(.system(size: 17, weight: weight)).foregroundStyle(color)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        }
    }
}

extension View {
    /// Подтверждение в виде алерта. `systemImage` оставлен для совместимости вызовов и не отображается.
    func ryConfirm(isPresented: Binding<Bool>, systemImage: String = "trash", title: String, message: String,
                   confirmTitle: String, extraTitle: String? = nil, onExtra: (() -> Void)? = nil,
                   onConfirm: @escaping () -> Void) -> some View {
        overlay {
            if isPresented.wrappedValue {
                RYConfirmDialog(title: title, message: message, confirmTitle: confirmTitle,
                                extraTitle: extraTitle,
                                onExtra: onExtra.map { extra in { isPresented.wrappedValue = false; extra() } },
                                onConfirm: { isPresented.wrappedValue = false; onConfirm() },
                                onCancel: { isPresented.wrappedValue = false })
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented.wrappedValue)
    }
}
