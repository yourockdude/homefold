import SwiftUI

/// Каркас модального листа формы: «Отмена · Заголовок · Действие» и прокручиваемое содержимое на сером фоне.
struct RYSheetScaffold<Content: View, Footer: View>: View {
    let title: String
    var cancelTitle = "Отмена"
    let confirmTitle: String
    var confirmEnabled = true
    var confirmIdentifier = "sheet.confirm"
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).ryFont(.headline).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                HStack {
                    Button(cancelTitle, action: onCancel).ryFont(.body).foregroundStyle(RYColor.accent)
                        .accessibilityIdentifier("sheet.cancel")
                    Spacer()
                    Button(confirmTitle, action: onConfirm).ryFont(.headline).foregroundStyle(RYColor.accent.opacity(confirmEnabled ? 1 : 0.4))
                        .disabled(!confirmEnabled).accessibilityIdentifier(confirmIdentifier)
                }
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, 22).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.s) { content }
                    .padding(.horizontal, RYSpacing.screen)
                    .padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(RYColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(RYColor.background)
        .presentationCornerRadius(RYRadius.sheet)
    }
}

extension RYSheetScaffold where Footer == EmptyView {
    init(title: String, cancelTitle: String = "Отмена", confirmTitle: String, confirmEnabled: Bool = true,
         confirmIdentifier: String = "sheet.confirm", onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, cancelTitle: cancelTitle, confirmTitle: confirmTitle, confirmEnabled: confirmEnabled,
                  confirmIdentifier: confirmIdentifier, onCancel: onCancel, onConfirm: onConfirm,
                  content: content, footer: { EmptyView() })
    }
}

/// Заголовок экрана: 34 bold, подзаголовок 15 и круглые стеклянные действия справа.
struct RYScreenHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title).ryFont(.title).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                actions
            }
            if let subtitle { Text(subtitle).ryFont(.callout).foregroundStyle(RYColor.muted) }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 12)
    }
}

extension RYScreenHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, actions: { EmptyView() })
    }
}
