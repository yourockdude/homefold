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
                .transition(.opacity)
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
            .background(RYColor.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: RYRadius.sheet))
            .clipShape(RoundedRectangle(cornerRadius: RYRadius.sheet))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private func row(_ title: String, color: Color, weight: Font.Weight, id: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(RYColor.separator).frame(height: 0.5)
            Button(action: action) {
                Text(title).ryFont(weight == .semibold ? RYFontStyle.headline : RYFontStyle.body).foregroundStyle(color)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        }
    }
}

/// Признак «на экране показан диалог»: корневой экран затемняет по нему плавающую панель вкладок.
@Observable
@MainActor
final class DialogDimming {
    var isActive = false
}

private struct ConfirmModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let confirmTitle: String
    let extraTitle: String?
    let onExtra: (() -> Void)?
    let onConfirm: () -> Void
    @Environment(DialogDimming.self) private var dimming: DialogDimming?

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    RYConfirmDialog(title: title, message: message, confirmTitle: confirmTitle,
                                    extraTitle: extraTitle,
                                    onExtra: onExtra.map { extra in { isPresented = false; extra() } },
                                    onConfirm: { isPresented = false; onConfirm() },
                                    onCancel: { isPresented = false })
                }
            }
            .animation(RYMotion.dialog, value: isPresented)
            .onChange(of: isPresented) { _, shown in dimming?.isActive = shown }
            .onDisappear { if isPresented { dimming?.isActive = false } }
    }
}

extension View {
    /// Подтверждение в виде алерта. `systemImage` оставлен для совместимости вызовов и не отображается.
    func ryConfirm(isPresented: Binding<Bool>, systemImage: String = "trash", title: String, message: String,
                   confirmTitle: String, extraTitle: String? = nil, onExtra: (() -> Void)? = nil,
                   onConfirm: @escaping () -> Void) -> some View {
        modifier(ConfirmModifier(isPresented: isPresented, title: title, message: message, confirmTitle: confirmTitle,
                                 extraTitle: extraTitle, onExtra: onExtra, onConfirm: onConfirm))
    }
}
