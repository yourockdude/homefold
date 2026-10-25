import SwiftUI

/// Цветовые токены HomeFold из гайда стилей Figma (Text & Icons, Surface, Background, Outlines, Gradients, Palette).
/// Каждый токен — цвет в `Colors.xcassets` с вариантами Any/Dark, поэтому светлая и тёмная темы работают автоматически.
/// Имена свойств ниже — смысловые роли приложения; сырые токены доступны через `RYToken`.
public enum RYColor {
    private static func token(_ name: String) -> Color { Color(name, bundle: .module) }

    // Фоны и поверхности
    /// Фон экрана: bg-contrast (светлая) / bg-secondary (тёмная).
    public static let background = token("screen-background")
    /// Карточки и поля: surface-neutral-primary.
    public static let surface = token("surface-primary")
    /// Вторичная поверхность (переключатель, скелетон): surface-neutral-secondary.
    public static let surfaceSecondary = token("surface-secondary")

    // Линии
    /// Разделители внутри карточек и в алертах: outline-neutral-tertiary.
    public static let divider = token("outline-tertiary")
    public static let separator = token("outline-tertiary")
    public static let border = token("outline-quaternary")
    /// Контур пустой отметки: outline-neutral-secondary.
    public static let checkBorder = token("outline-secondary")

    // Текст и значки
    public static let ink = token("text-primary")
    /// Вторичный текст: text-neutral-secondary.
    public static let muted = token("text-secondary")
    public static let placeholder = token("text-tertiary")
    public static let softInk = token("text-softPrimary")
    /// Акцентный текст, ссылки, значки: text-accent-primary.
    public static let accent = token("text-accent")
    /// Заливка акцентных элементов (кнопки, выбранный день, отметки): surface-accent-primary.
    public static let accentFill = token("surface-accent-primary")
    public static let primary = accentFill
    /// Подложка акцентных плашек и выбранных пилюль: surface-accent-tsp.
    public static let accentTint = token("surface-accent-tsp")
    public static let accentInk = token("text-accent-ink")
    /// Текст на акцентной заливке и на фото: text-constant-light.
    public static let onAccent = token("text-constant-light")
    /// Затемнение низа фотографии.
    public static let coverShade = token("surface-constant-dark")

    // Статусы
    public static let danger = token("text-error")
    public static let dangerTint = token("surface-error-minor")
    public static let success = token("text-success")
    public static let successTint = token("surface-success-minor")
    public static let warning = token("text-warning")
    public static let warningTint = token("surface-warning-minor")

    // Цвета аватаров и значков категорий (Palette: soft / strong)
    public static let peach = token("palette-orange-soft")
    public static let peachInk = token("palette-orange-strong")
    public static let sky = token("palette-blueGray-soft")
    public static let skyInk = token("palette-blueGray-strong")
    public static let lilac = token("palette-purple-soft")
    public static let lilacInk = token("palette-purple-strong")
    public static let mint = token("palette-green-soft")
    public static let mintInk = token("palette-green-strong")

    /// Затемнение под диалогом.
    public static let scrim = token("surface-constant-dark").opacity(0.45)
}

/// Сырые токены гайда стилей по их именам в Figma (для редких случаев, когда нужен точный токен).
public enum RYToken {
    public static func color(_ name: String) -> Color { Color(name, bundle: .module) }

    public enum Palette: String, CaseIterable {
        case blueGray, inkBlue, skyBlue, teal, green, spring, gold, orange, red, pink, orchid, purple
        public var soft: Color { RYToken.color("palette-\(rawValue)-soft") }
        public var strong: Color { RYToken.color("palette-\(rawValue)-strong") }
        /// Полупрозрачный вариант мягкого цвета.
        public var tsp: Color { RYToken.color("palette-\(rawValue)-tsp") }
    }

    public static let gradientPeach = [color("gradient-peach-1"), color("gradient-peach-2")]
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

/// Смысловые стили текста приложения. Каждый указывает на шрифтовой токен из Figma (`RYType`);
/// чтобы перенастроить типографику, меняется только это соответствие.
public enum RYFontStyle {
    /// Логотип.
    case brand
    /// Заголовок экрана.
    case title
    /// Крупные числа.
    case number
    /// Название на обложке, заголовки состояний.
    case heading
    /// Заголовок раздела.
    case section
    /// Заголовок строки, подпись кнопки.
    case headline
    /// Основной текст строки.
    case body
    /// Основной текст, начертание полужирное.
    case bodyMedium
    /// Вторичные подписи, действия-ссылки.
    case callout
    /// Подписи под строкой.
    case subhead
    /// Мелкие подписи, заголовки групп.
    case caption
    /// Подписи вкладок.
    case micro

    public var token: RYFontToken {
        switch self {
        case .brand, .number, .heading: RYType.h3B
        case .title: RYType.h2B
        case .section: RYType.h4B
        case .headline, .bodyMedium: RYType.bodyMB
        case .body: RYType.bodyMN
        case .callout: RYType.bodySN
        case .subhead, .caption: RYType.bodyXSN
        case .micro: RYType.bodyXXSN
        }
    }
}

public extension View {
    func ryFont(_ style: RYFontStyle) -> some View { ryFont(style.token) }
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
