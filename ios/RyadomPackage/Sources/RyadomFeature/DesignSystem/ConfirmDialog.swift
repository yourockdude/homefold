import SwiftUI

/// Диалог подтверждения из макета: белая карточка по центру на затемнении.
struct RYConfirmDialog: View {
    let systemImage: String
    let title: String
    let message: String
    let confirmTitle: String
    var extraTitle: String?
    var onExtra: (() -> Void)?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color(hex: 0x183C2D).opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RYSpacing.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(RYColor.danger)
                    .accessibilityHidden(true)
                Text(title).ryFont(.heading).foregroundStyle(RYColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(message).ryFont(.body).foregroundStyle(RYColor.muted)
                VStack(spacing: RYSpacing.s) {
                    Button(confirmTitle, action: onConfirm).buttonStyle(.ryDestructive)
                    if let extraTitle, let onExtra {
                        Button(extraTitle, action: onExtra).buttonStyle(.ryDestructive)
                    }
                    Button("Отмена", action: onCancel).buttonStyle(.rySecondary)
                }
                .padding(.top, RYSpacing.xs)
            }
            .padding(RYSpacing.screen)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.sheet))
            .padding(.horizontal, RYSpacing.screen)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

extension View {
    func ryConfirm(isPresented: Binding<Bool>, systemImage: String = "trash", title: String, message: String,
                   confirmTitle: String, extraTitle: String? = nil, onExtra: (() -> Void)? = nil,
                   onConfirm: @escaping () -> Void) -> some View {
        overlay {
            if isPresented.wrappedValue {
                RYConfirmDialog(systemImage: systemImage, title: title, message: message, confirmTitle: confirmTitle,
                                extraTitle: extraTitle,
                                onExtra: onExtra.map { extra in { isPresented.wrappedValue = false; extra() } },
                                onConfirm: { isPresented.wrappedValue = false; onConfirm() },
                                onCancel: { isPresented.wrappedValue = false })
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented.wrappedValue)
    }
}
