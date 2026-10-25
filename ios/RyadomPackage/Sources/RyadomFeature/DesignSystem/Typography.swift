import SwiftUI
import CoreText

/// Семейство шрифта из дизайна. Display — для заголовков и UI-компонентов, Text — для чтения.
public enum RYFontFamily: Sendable {
    case display, text

    /// PostScript-имена по начертаниям. Первый найденный в системе вариант используется, иначе — SF Pro.
    func postScriptNames(for weight: RYFontWeight) -> [String] {
        let base = self == .display ? "SBSansDisplay" : "SBSansText"
        switch weight {
        case .regular: return ["\(base)-Regular"]
        case .medium: return ["\(base)-Medium"]
        case .semibold: return ["\(base)-SemiBold", "\(base)-Semibold"]
        case .bold: return ["\(base)-Bold"]
        }
    }
}

public enum RYFontWeight: Sendable {
    case regular, medium, semibold, bold

    var swiftUI: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    var ui: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// Шрифтовой токен из Figma («Fonts»): семейство, размер, межстрочный интервал, начертание и трекинг.
public struct RYFontToken: Equatable, Sendable {
    public let name: String
    public let family: RYFontFamily
    public let size: CGFloat
    public let lineHeight: CGFloat
    public let weight: RYFontWeight
    /// Межбуквенный интервал в процентах от размера (в Figma: −2 = −2 %).
    public let tracking: CGFloat

    init(_ name: String, _ family: RYFontFamily, _ size: CGFloat, _ lineHeight: CGFloat, _ weight: RYFontWeight, _ tracking: CGFloat) {
        self.name = name
        self.family = family
        self.size = size
        self.lineHeight = lineHeight
        self.weight = weight
        self.tracking = tracking
    }

    public static func == (lhs: RYFontToken, rhs: RYFontToken) -> Bool { lhs.name == rhs.name }

    /// Межбуквенный интервал в пунктах для заданного размера.
    func trackingPoints(at size: CGFloat) -> CGFloat { size * tracking / 100 }
}

/// Шкала токенов. Названия повторяют Figma: H — Headline, Body, Text, Display; суффикс B/M/N — Bold/Medium(Semibold)/Normal.
public enum RYType {
    // Headline
    public static let h0B = RYFontToken("Headline 0 B", .display, 48, 48, .bold, -2)
    public static let h0N = RYFontToken("Headline 0 N", .display, 48, 48, .regular, -2)
    public static let h1B = RYFontToken("Headline 1 B", .display, 40, 48, .bold, -3)
    public static let h1N = RYFontToken("Headline 1 N", .display, 40, 48, .regular, -4)
    public static let h2B = RYFontToken("Headline 2 B", .display, 32, 36, .semibold, -4)
    public static let h2N = RYFontToken("Headline 2 N", .display, 32, 36, .regular, -2)
    public static let h3B = RYFontToken("Headline 3 B", .display, 24, 30, .bold, -1.5)
    public static let h3M = RYFontToken("Headline 3 M", .display, 24, 30, .semibold, -3)
    public static let h3N = RYFontToken("Headline 3 N", .display, 24, 30, .regular, -3)
    public static let h4B = RYFontToken("Headline 4 B", .display, 20, 26, .bold, -1.5)
    public static let h4M = RYFontToken("Headline 4 M", .display, 20, 26, .semibold, -1)
    public static let h4N = RYFontToken("Headline 4 N", .display, 20, 26, .regular, -1)

    // Body — UI-компоненты: кнопки, чипсы, теги, меню, лейблы
    public static let bodyLB = RYFontToken("Body L B", .display, 18, 24, .semibold, -2)
    public static let bodyLN = RYFontToken("Body L N", .display, 18, 24, .regular, -1.5)
    public static let bodyMB = RYFontToken("Body M B", .display, 16, 20, .semibold, -1.5)
    public static let bodyMN = RYFontToken("Body M N", .display, 16, 20, .regular, -1.5)
    public static let bodySB = RYFontToken("Body S B", .display, 14, 16, .semibold, -1)
    public static let bodySN = RYFontToken("Body S N", .display, 14, 16, .regular, -1)
    public static let bodyXSB = RYFontToken("Body XS B", .display, 12, 14, .semibold, -2)
    public static let bodyXSN = RYFontToken("Body XS N", .display, 12, 14, .regular, -2)
    public static let bodyXXSB = RYFontToken("Body XXS B", .display, 10, 12, .semibold, 0)
    public static let bodyXXSM = RYFontToken("Body XXS M", .display, 10, 12, .medium, 0)
    public static let bodyXXSN = RYFontToken("Body XXS N", .display, 10, 12, .regular, 0)

    // Text — чтение: параграфы, статьи, описания
    public static let textLB = RYFontToken("Text L B", .text, 18, 28, .semibold, -2)
    public static let textLN = RYFontToken("Text L N", .text, 18, 28, .regular, -2)
    public static let textMB = RYFontToken("Text M B", .text, 16, 26, .semibold, -1.5)
    public static let textMN = RYFontToken("Text M N", .text, 16, 26, .regular, -1.5)
    public static let textSB = RYFontToken("Text S B", .text, 14, 20, .semibold, -1.5)
    public static let textSN = RYFontToken("Text S N", .text, 14, 20, .regular, -1.5)
    public static let textXSB = RYFontToken("Text XS B", .text, 12, 16, .semibold, -2)
    public static let textXSN = RYFontToken("Text XS N", .text, 12, 16, .regular, -2)

    // Display — крупные акценты: онбординг, большие цифры, сплэш
    public static let display1B = RYFontToken("Display 1 B", .display, 128, 144, .semibold, -3)
    public static let display1N = RYFontToken("Display 1 N", .display, 128, 144, .regular, -3)
    public static let display2B = RYFontToken("Display 2 B", .display, 88, 88, .semibold, -2)
    public static let display2N = RYFontToken("Display 2 N", .display, 88, 88, .regular, -2)

    public static let all: [RYFontToken] = [
        h0B, h0N, h1B, h1N, h2B, h2N, h3B, h3M, h3N, h4B, h4M, h4N,
        bodyLB, bodyLN, bodyMB, bodyMN, bodySB, bodySN, bodyXSB, bodyXSN, bodyXXSB, bodyXXSM, bodyXXSN,
        textLB, textLN, textMB, textMN, textSB, textSN, textXSB, textXSN,
        display1B, display1N, display2B, display2N,
    ]
}

/// Подбор шрифта по токену: SB Sans, если файлы подключены, иначе системный SF Pro с теми же параметрами.
enum RYFontResolver {
    static func customName(for token: RYFontToken) -> String? {
        token.family.postScriptNames(for: token.weight).first { UIFont(name: $0, size: 12) != nil }
    }

    static func font(for token: RYFontToken, size: CGFloat) -> Font {
        if let name = customName(for: token) { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: token.weight.swiftUI)
    }

    /// Естественная высота строки шрифта — нужна, чтобы довести интервал до значения из токена.
    static func naturalLineHeight(for token: RYFontToken, size: CGFloat) -> CGFloat {
        if let name = customName(for: token), let font = UIFont(name: name, size: size) { return font.lineHeight }
        return UIFont.systemFont(ofSize: size, weight: token.weight.ui).lineHeight
    }
}

/// Подключает файлы шрифтов из `Resources/Fonts` (если они есть). Безопасно вызывать повторно.
public enum RYFonts {
    @MainActor private static var registered = false

    @MainActor
    public static func register() {
        guard !registered else { return }
        registered = true
        let urls = ["otf", "ttf"].flatMap { Bundle.module.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, nil)
    }
}

private struct RYTokenFontModifier: ViewModifier {
    let token: RYFontToken
    @ScaledMetric private var size: CGFloat

    init(token: RYFontToken) {
        self.token = token
        let style: Font.TextStyle = token.size >= 32 ? .largeTitle : (token.size >= 24 ? .title : (token.size >= 20 ? .title3
            : (token.size >= 16 ? .body : (token.size >= 14 ? .callout : (token.size >= 12 ? .footnote : .caption2)))))
        self._size = ScaledMetric(wrappedValue: token.size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        let scale = size / token.size
        let spacing = max(0, token.lineHeight * scale - RYFontResolver.naturalLineHeight(for: token, size: size))
        return content
            .font(RYFontResolver.font(for: token, size: size))
            .tracking(token.trackingPoints(at: size))
            .lineSpacing(spacing)
    }
}

public extension View {
    /// Применяет шрифтовой токен из Figma: шрифт, размер (с Dynamic Type), трекинг и межстрочный интервал.
    func ryFont(_ token: RYFontToken) -> some View { modifier(RYTokenFontModifier(token: token)) }
}
