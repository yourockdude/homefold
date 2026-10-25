import SwiftUI

/// Палитра аватара участника: пастельный фон + цвет буквы.
public enum AvatarTone: Int, CaseIterable, Sendable {
    case peach, sky, lilac, mint

    public var background: Color {
        switch self {
        case .peach: RYColor.peach
        case .sky: RYColor.sky
        case .lilac: RYColor.lilac
        case .mint: RYColor.accentTint
        }
    }

    public var ink: Color {
        switch self {
        case .peach: RYColor.peachInk
        case .sky: RYColor.skyInk
        case .lilac: RYColor.lilacInk
        case .mint: RYColor.accent
        }
    }
}

public struct AvatarView: View {
    let name: String
    let tone: AvatarTone
    var diameter: CGFloat = 30

    public init(name: String, tone: AvatarTone, diameter: CGFloat = 30) {
        self.name = name
        self.tone = tone
        self.diameter = diameter
    }

    public var body: some View {
        Text(name.prefix(1).uppercased())
            .font(.system(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(tone.ink)
            .frame(width: diameter, height: diameter)
            .background(tone.background, in: Circle())
            .accessibilityLabel(name)
    }
}

public struct RYCard<Content: View>: View {
    var padding: CGFloat = RYSpacing.s + 2
    @ViewBuilder var content: Content

    public init(padding: CGFloat = RYSpacing.s + 2, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
    }
}

public struct RYPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ryFont(.bodyMedium)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RYColor.accent.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4),
                in: RoundedRectangle(cornerRadius: RYRadius.card)
            )
    }
}

public struct RYSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ryFont(.bodyMedium)
            .foregroundStyle(RYColor.accent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RYColor.accentTint.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: RYRadius.card))
    }
}

public struct RYDestructiveButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ryFont(.bodyMedium)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RYColor.danger.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: RYRadius.card))
    }
}

public extension ButtonStyle where Self == RYPrimaryButtonStyle {
    static var ryPrimary: RYPrimaryButtonStyle { .init() }
}
public extension ButtonStyle where Self == RYSecondaryButtonStyle {
    static var rySecondary: RYSecondaryButtonStyle { .init() }
}
public extension ButtonStyle where Self == RYDestructiveButtonStyle {
    static var ryDestructive: RYDestructiveButtonStyle { .init() }
}

/// Круглый чекбокс со скруглённым квадратом как в макете.
public struct RYCheckbox: View {
    let isOn: Bool

    public init(isOn: Bool) { self.isOn = isOn }

    public var body: some View {
        RoundedRectangle(cornerRadius: RYRadius.chip)
            .fill(isOn ? RYColor.accent : RYColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: RYRadius.chip)
                    .stroke(isOn ? RYColor.accent : RYColor.checkBorder, lineWidth: 1.3)
            )
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 23, height: 23)
            .accessibilityHidden(true)
    }
}

public struct RYSectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack {
            Text(title).ryFont(.section).foregroundStyle(RYColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .ryFont(.caption).fontWeight(.medium)
                    .foregroundStyle(RYColor.accent)
            }
        }
    }
}

public struct RYStatusBanner: View {
    public enum Kind { case offline, error, info }
    let kind: Kind
    let text: String
    var retryTitle: String?
    var retry: (() -> Void)?

    public init(kind: Kind, text: String, retryTitle: String? = nil, retry: (() -> Void)? = nil) {
        self.kind = kind
        self.text = text
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var body: some View {
        HStack(spacing: RYSpacing.xs) {
            Image(systemName: kind == .offline ? "wifi.slash" : (kind == .error ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath"))
                .font(.system(size: 14))
            Text(text).ryFont(.caption).frame(maxWidth: .infinity, alignment: .leading)
            if let retryTitle, let retry {
                Button(retryTitle, action: retry).ryFont(.caption).fontWeight(.semibold)
            }
        }
        .foregroundStyle(kind == .error ? RYColor.danger : RYColor.accent)
        .padding(RYSpacing.s)
        .background(kind == .error ? RYColor.dangerTint : RYColor.accentTint,
                    in: RoundedRectangle(cornerRadius: RYSpacing.s))
    }
}

public struct RYEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    public init(systemImage: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: RYSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(RYColor.accent)
                .frame(width: 64, height: 64)
                .background(RYColor.accentTint, in: Circle())
            Text(title).ryFont(.section).foregroundStyle(RYColor.ink).multilineTextAlignment(.center)
            Text(message).ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.ryPrimary).padding(.horizontal, RYSpacing.screen)
            }
        }
        .padding(RYSpacing.screen)
        .frame(maxWidth: .infinity)
    }
}

/// Поле ввода в стиле макета с подписью и текстом ошибки.
public struct RYTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var error: String?
    var keyboard: UIKeyboardType = .default

    public init(_ title: String, text: Binding<String>, placeholder: String = "", error: String? = nil, keyboard: UIKeyboardType = .default) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.error = error
        self.keyboard = keyboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).ryFont(.caption).foregroundStyle(RYColor.muted)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .ryFont(.body)
                .padding(.horizontal, RYSpacing.s + 2)
                .frame(minHeight: 48)
                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: RYRadius.card)
                        .stroke(error == nil ? RYColor.border : RYColor.danger, lineWidth: 1)
                )
            if let error {
                Text(error).ryFont(.caption).foregroundStyle(RYColor.danger)
            }
        }
    }
}
