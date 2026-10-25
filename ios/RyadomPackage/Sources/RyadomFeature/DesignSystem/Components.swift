import SwiftUI

/// Палитра аватара участника: пастельный фон + цвет буквы.
public enum AvatarTone: Int, CaseIterable, Sendable {
    case peach, sky, lilac, mint

    public var background: Color {
        switch self {
        case .peach: RYColor.peach
        case .sky: RYColor.sky
        case .lilac: RYColor.lilac
        case .mint: RYColor.mint
        }
    }

    public var ink: Color {
        switch self {
        case .peach: RYColor.peachInk
        case .sky: RYColor.skyInk
        case .lilac: RYColor.lilacInk
        case .mint: RYColor.mintInk
        }
    }
}

public struct AvatarView: View {
    let name: String
    let tone: AvatarTone
    var diameter: CGFloat = 26

    public init(name: String, tone: AvatarTone, diameter: CGFloat = 26) {
        self.name = name
        self.tone = tone
        self.diameter = diameter
    }

    public var body: some View {
        Text(name.prefix(1).uppercased())
            .font(.system(size: diameter * 0.43, weight: .semibold))
            .foregroundStyle(tone.ink)
            .frame(width: diameter, height: diameter)
            .background(tone.background, in: Circle())
            .accessibilityLabel(name)
    }
}

// MARK: Карточки и группы

/// Белая карточка r20.
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

/// Группа строк в одной белой карточке: поля по 16 pt, тонкие разделители между строками.
/// Использование: `RYListGroup { row; RYListDivider(); row }`.
public struct RYListGroup<Content: View>: View {
    @ViewBuilder var content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
    }
}

/// Разделитель 0,5 pt. `inset` отступает слева (под значок или чекбокс).
public struct RYListDivider: View {
    var inset: CGFloat = 0
    public init(inset: CGFloat = 0) { self.inset = inset }
    public var body: some View {
        Rectangle().fill(RYColor.divider).frame(height: 0.5).padding(.leading, inset)
    }
}

/// Строка: ведущий элемент, заголовок 17 и подпись 13, замыкающий элемент.
public struct RYListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var minHeight: CGFloat = 62
    var titleStyle: RYFontStyle = .body
    var titleColor: Color = RYColor.ink
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, minHeight: CGFloat = 62, titleStyle: RYFontStyle = .body,
                titleColor: Color = RYColor.ink,
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.minHeight = minHeight
        self.titleStyle = titleStyle
        self.titleColor = titleColor
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(title).ryFont(titleStyle).foregroundStyle(titleColor)
                if let subtitle { Text(subtitle).ryFont(.subhead).foregroundStyle(RYColor.muted) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 11)
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
    }
}

public extension RYListRow where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, minHeight: CGFloat = 62) {
        self.init(title, subtitle: subtitle, minHeight: minHeight, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

// MARK: Кнопки

/// Основная кнопка: капсула, акцентный фон, подпись 17 semibold.
public struct RYPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ryFont(.headline)
            .foregroundStyle(RYColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RYColor.accentFill.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Вторичная кнопка: капсула с бледно-зелёным фоном.
public struct RYSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ryFont(.headline)
            .foregroundStyle(RYColor.accent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RYColor.accentTint.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

public struct RYDestructiveButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ryFont(.headline)
            .foregroundStyle(RYColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RYColor.danger.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
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

/// Текстовая кнопка-ссылка (акцентный цвет 17), например «Отмена переноса».
public struct RYLinkButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ryFont(.bodyMedium)
            .foregroundStyle(RYColor.accent.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}
public extension ButtonStyle where Self == RYLinkButtonStyle {
    static var ryLink: RYLinkButtonStyle { .init() }
}

// MARK: Стекло

/// Матовая «стеклянная» подложка плавающих элементов: белая 85%, блюр, тонкая белая обводка, мягкая тень.
public struct RYGlassBackground<S: Shape>: ViewModifier {
    let shape: S

    public func body(content: Content) -> some View {
        content
            .background(RYColor.surface.opacity(0.85), in: shape)   // поверх блюра
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(RYColor.surface.opacity(0.9), lineWidth: 0.7))
            .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
    }
}

public extension View {
    func ryGlass<S: Shape>(in shape: S) -> some View { modifier(RYGlassBackground(shape: shape)) }
}

/// Круглая кнопка действия на стекле (44 pt): «…», «+».
public struct RYGlassCircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    public init(systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) { RYGlassCircleLabel(systemImage: systemImage) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }
}

/// Внешний вид круглой стеклянной кнопки — для `Menu` и других контейнеров.
public struct RYGlassCircleLabel: View {
    let systemImage: String
    public init(systemImage: String) { self.systemImage = systemImage }
    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(RYColor.accent)
            .frame(width: 44, height: 44)
            .ryGlass(in: Circle())
    }
}

/// «‹ Дела» — текстовая кнопка возврата в стиле iOS.
public struct RYBackButton: View {
    let title: String
    let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                Text(title).ryFont(.body)
            }
            .foregroundStyle(RYColor.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Назад: \(title)")
        .accessibilityIdentifier("nav.back")
    }
}

// MARK: Элементы

/// Круглая отметка выполнения 26 pt: пустая с серым контуром или залитая зелёной с белой галкой.
public struct RYCheckbox: View {
    let isOn: Bool

    public init(isOn: Bool) { self.isOn = isOn }

    public var body: some View {
        ZStack {
            Circle().fill(isOn ? RYColor.accentFill : RYColor.surface)
            Circle().stroke(isOn ? RYColor.accentFill : RYColor.checkBorder, lineWidth: 1.3)
            if isOn {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(RYColor.onAccent)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 26, height: 26)
        .scaleEffect(isOn ? 1 : 0.98)
        .animation(RYMotion.snappy, value: isOn)
        .sensoryFeedback(trigger: isOn) { _, new in new ? .success : .impact(flexibility: .soft) }
        .accessibilityHidden(true)
    }
}

/// Заголовок раздела: 21 bold и необязательное действие 15 акцентным цветом.
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
                    .ryFont(.callout)
                    .foregroundStyle(RYColor.accent)
            }
        }
    }
}

/// Мелкий заголовок группы: «МОЛОЧНОЕ И ЯЙЦА».
public struct RYGroupCaption: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased()).ryFont(.caption).foregroundStyle(RYColor.muted).padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Информационная плашка: бледно-зелёная (или красная), иконка, заголовок 15 semibold и текст 13.
public struct RYNotice: View {
    let systemImage: String
    var title: String?
    let text: String
    var tint: Color = RYColor.accentTint
    var ink: Color = RYColor.accent

    public init(systemImage: String, title: String? = nil, text: String, tint: Color = RYColor.accentTint, ink: Color = RYColor.accent) {
        self.systemImage = systemImage
        self.title = title
        self.text = text
        self.tint = tint
        self.ink = ink
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .light)).foregroundStyle(ink).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                if let title { Text(title).ryFont(.callout).fontWeight(.semibold).foregroundStyle(ink) }
                Text(text).ryFont(.subhead).foregroundStyle(title == nil ? ink : RYColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: RYRadius.card - 4))
        .accessibilityElement(children: .combine)
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
            Text(text).ryFont(.subhead).frame(maxWidth: .infinity, alignment: .leading)
            if let retryTitle, let retry {
                Button(retryTitle, action: retry).ryFont(.subhead).fontWeight(.semibold)
            }
        }
        .foregroundStyle(kind == .error ? RYColor.danger : RYColor.accent)
        .padding(RYSpacing.s)
        .background(kind == .error ? RYColor.dangerTint : RYColor.accentTint,
                    in: RoundedRectangle(cornerRadius: RYRadius.card - 4))
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
                .background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: 20))
            Text(title).ryFont(.section).foregroundStyle(RYColor.ink).multilineTextAlignment(.center)
            Text(message).ryFont(.callout).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.ryPrimary).padding(.horizontal, RYSpacing.screen)
            }
        }
        .padding(RYSpacing.screen)
        .frame(maxWidth: .infinity)
    }
}

/// Поле ввода с подписью и текстом ошибки.
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
            Text(title).ryFont(.subhead).foregroundStyle(RYColor.muted)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .ryFont(.body)
                .ryField(isError: error != nil)
            if let error {
                Text(error).ryFont(.subhead).foregroundStyle(RYColor.danger)
            }
        }
    }
}

/// Сегментированный переключатель («Все / Мои · 1 / По участникам»).
public struct RYSegmentedControl<ID: Hashable>: View {
    public struct Segment: Identifiable {
        public let id: ID
        public let title: String
        public init(id: ID, title: String) { self.id = id; self.title = title }
    }

    let segments: [Segment]
    let selection: ID
    let onSelect: (ID) -> Void
    @Namespace private var ns

    public init(segments: [Segment], selection: ID, onSelect: @escaping (ID) -> Void) {
        self.segments = segments
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { segment in
                let selected = segment.id == selection
                Button { withAnimation(.easeOut(duration: 0.18)) { onSelect(segment.id) } } label: {
                    Text(segment.title).ryFont(.callout).fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? RYColor.ink : RYColor.muted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selected {
                                Capsule().fill(RYColor.surface).shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "segment", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RYColor.surfaceSecondary, in: Capsule())
    }
}
