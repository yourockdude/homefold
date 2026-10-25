import SwiftUI

/// Сплэш: анимированный цветовой фон в цветах приложения (случайный тип и угол при каждом запуске) и логотип HomeFold с белым названием.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoVisible = false
    /// Вариант фона выбирается один раз за запуск.
    @State private var shader = SplashShaderConfig.debugOverride ?? .random()

    var body: some View {
        ZStack {
            SplashBackground(config: shader, animated: !reduceMotion)
            BrandMark(style: .splash, color: RYColor.onAccent)
                .opacity(logoVisible ? 1 : 0)
                .scaleEffect(logoVisible ? 1 : 0.94)
                .blur(radius: logoVisible ? 0 : 6)
        }
        .ignoresSafeArea()
        .task { withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 1.0)) { logoVisible = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HomeFold")
        .accessibilityIdentifier("splash")
    }
}
