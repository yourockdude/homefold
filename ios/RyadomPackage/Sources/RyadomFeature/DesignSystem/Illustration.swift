import SwiftUI

/// Трёхмерные иллюстрации состояний (PNG с прозрачным фоном из `Assets.xcassets`).
public enum RYIllustrationKind: String, Sendable {
    /// Папка с документами — пустое хранилище.
    case folder = "DocumentsEmpty"
    /// Объектив — нужен доступ к камере.
    case camera = "IllustrationCamera"
    /// Лупа — ничего не найдено.
    case search = "IllustrationSearch"
    /// Замок — раздел защищён.
    case lock = "IllustrationLock"
    /// Корзина с продуктами — пустой список покупок.
    case basket = "IllustrationBasket"
    /// Календарь — свободный день.
    case calendar = "IllustrationCalendar"
    /// Облако — не удалось загрузить данные.
    case cloud = "IllustrationCloud"
    /// Микрофон — голосовой ввод.
    case microphone = "IllustrationMicrophone"
}

/// Иллюстрация состояния: вписывается в заданную высоту, для VoiceOver скрыта как декоративная.
public struct RYIllustration: View {
    /// Единая высота иллюстраций состояний (как в «Делах»). Менять размер на экранах не нужно — только здесь.
    public static let standardHeight: CGFloat = 150

    let kind: RYIllustrationKind
    var height: CGFloat

    public init(_ kind: RYIllustrationKind, height: CGFloat = RYIllustration.standardHeight) {
        self.kind = kind
        self.height = height
    }

    public var body: some View {
        Image(kind.rawValue, bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}
