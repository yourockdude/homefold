import SwiftUI

/// Анимации интерфейса: короткие системные пружины iOS 17+ без лишнего движения.
/// Для перехода между вкладками и крупных смещений учитывается «Уменьшить движение».
public enum RYMotion {
    /// Небольшие элементы: выбор, отметка, число.
    public static let snappy = Animation.snappy(duration: 0.28, extraBounce: 0.06)
    /// Плавное появление и исчезновение блоков.
    public static let smooth = Animation.smooth(duration: 0.3)
    /// Диалоги: мягкая пружина с лёгким «оседанием».
    public static let dialog = Animation.spring(duration: 0.32, bounce: 0.12)

    /// Переход между вкладками. При «Уменьшить движение» — короткое растворение без сдвига.
    public static func tab(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.34)
    }

    /// Горизонтальный сдвиг контента вкладки при переходе: чем дальше вкладка, тем заметнее, но не больше 16 pt.
    static func tabOffset(distance: Int, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, distance != 0 else { return 0 }
        return CGFloat(max(-1, min(1, distance))) * 16
    }
}
