import SwiftUI

/// Дизайн-токены «рядом». Значения сняты с макета Figma (Семейный обзор и др.).
public enum RYColor {
    public static let background = Color(hex: 0xF7F7F2)
    public static let surface = Color.white
    public static let border = Color(hex: 0xE5E8DF)
    public static let checkBorder = Color(hex: 0xCDD5C9)

    public static let ink = Color(hex: 0x233C35)
    public static let muted = Color(hex: 0x7B857D)
    public static let primary = Color(hex: 0x233C35)
    public static let accent = Color(hex: 0x376653)
    public static let accentTint = Color(hex: 0xE8EFE7)
    public static let coverShade = Color(hex: 0x183C2D)

    public static let peach = Color(hex: 0xF7EBDD)
    public static let peachInk = Color(hex: 0xB7734F)
    public static let sky = Color(hex: 0xEAF0F5)
    public static let skyInk = Color(hex: 0x617D92)
    public static let lilac = Color(hex: 0xEDE9F2)
    public static let lilacInk = Color(hex: 0x857098)

    public static let danger = Color(hex: 0xB5483F)
    public static let dangerTint = Color(hex: 0xF8E6E3)
}

public enum RYSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 20
    public static let screen: CGFloat = 24
}

public enum RYRadius {
    public static let chip: CGFloat = 8
    public static let card: CGFloat = 16
    public static let cover: CGFloat = 22
    public static let sheet: CGFloat = 28
    public static let pill: CGFloat = 100
}

/// Размеры шрифта из макета; масштабируются с Dynamic Type.
public enum RYFontStyle {
    case brand, title, heading, section, body, bodyMedium, caption, micro

    var size: CGFloat {
        switch self {
        case .brand: 27
        case .title: 28
        case .heading: 22
        case .section: 18
        case .body, .bodyMedium: 13
        case .caption: 12
        case .micro: 10
        }
    }

    var weight: Font.Weight {
        switch self {
        case .brand, .title, .heading, .section: .semibold
        case .bodyMedium: .medium
        default: .regular
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .brand, .title: .title
        case .heading: .title2
        case .section: .headline
        case .body, .bodyMedium: .subheadline
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
