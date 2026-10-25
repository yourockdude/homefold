import SwiftUI

/// Дизайн-токены «рядом» (редизайн: холодный фон, чёрно-зелёный текст, карточки r20).
public enum RYColor {
    public static let background = Color(hex: 0xF2F2F7)
    public static let surface = Color.white
    /// Тонкие разделители внутри карточек (0,5 pt).
    public static let divider = Color(hex: 0xDCDDE0)
    public static let separator = Color(hex: 0xBFC2C6)
    public static let border = Color(hex: 0xE3E4E8)
    public static let checkBorder = Color(hex: 0xC7CBC8)

    public static let ink = Color(hex: 0x18251F)
    public static let muted = Color(hex: 0x6C716E)
    public static let primary = Color(hex: 0x376653)
    public static let accent = Color(hex: 0x376653)
    public static let accentTint = Color(hex: 0xE5EEE8)
    public static let coverShade = Color(hex: 0x122E24)

    public static let peach = Color(hex: 0xF5E7D8)
    public static let peachInk = Color(hex: 0x9C633F)
    public static let sky = Color(hex: 0xE5EDF4)
    public static let skyInk = Color(hex: 0x567487)
    public static let lilac = Color(hex: 0xEEE7F4)
    public static let lilacInk = Color(hex: 0x79618D)

    public static let danger = Color(hex: 0xC63830)
    public static let dangerTint = Color(hex: 0xF8E6E3)
    /// Затемнение под диалогом.
    public static let scrim = Color(hex: 0x18251F).opacity(0.45)
}

public enum RYSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 20
    /// Горизонтальное поле экрана.
    public static let screen: CGFloat = 20
    /// Резерв под плавающую панель вкладок (66 pt панель + зазор).
    public static let tabBarReserve: CGFloat = 78
}

public enum RYRadius {
    public static let chip: CGFloat = 8
    public static let field: CGFloat = 14
    public static let card: CGFloat = 20
    public static let cover: CGFloat = 22
    public static let sheet: CGFloat = 28
    public static let pill: CGFloat = 100
}

/// Размеры шрифта из макета. Заголовки — системный шрифт (SF Pro) Bold; масштабируются с Dynamic Type.
public enum RYFontStyle {
    /// 27 bold — логотип.
    case brand
    /// 34 bold — заголовок экрана.
    case title
    /// 28 bold — крупные числа.
    case number
    /// 24 bold — название на обложке.
    case heading
    /// 21 bold — заголовок раздела.
    case section
    /// 17 semibold — заголовок строки / кнопки.
    case headline
    /// 17 regular — основной текст строки.
    case body
    /// 17 medium.
    case bodyMedium
    /// 15 regular — вторичные подписи, действия-ссылки.
    case callout
    /// 13 regular — подписи под строкой.
    case subhead
    /// 12 regular — мелкие подписи, заголовки групп.
    case caption
    /// 10 — подписи вкладок.
    case micro

    var size: CGFloat {
        switch self {
        case .brand: 27
        case .title: 34
        case .number: 28
        case .heading: 24
        case .section: 21
        case .headline, .body, .bodyMedium: 17
        case .callout: 15
        case .subhead: 13
        case .caption: 12
        case .micro: 10
        }
    }

    var weight: Font.Weight {
        switch self {
        case .brand, .title, .number, .heading, .section: .bold
        case .headline: .semibold
        case .bodyMedium: .medium
        default: .regular
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .brand, .title: .largeTitle
        case .number, .heading: .title
        case .section: .title3
        case .headline, .body, .bodyMedium: .body
        case .callout: .callout
        case .subhead: .footnote
        case .caption: .caption
        case .micro: .caption2
        }
    }
}

private struct RYFontModifier: ViewModifier {
    let style: RYFontStyle
    @ScaledMetric private var size: CGFloat

    init(style: RYFontStyle) {
        self.style = style
        self._size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: style.weight))
    }
}

public extension View {
    func ryFont(_ style: RYFontStyle) -> some View {
        modifier(RYFontModifier(style: style))
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
