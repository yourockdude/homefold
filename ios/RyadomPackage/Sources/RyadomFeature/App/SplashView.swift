import SwiftUI

/// Сплэш: анимированный цветовой фон в цветах приложения и белый логотип «рядом».
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoVisible = false

    var body: some View {
        ZStack {
            SplashBackground(animated: !reduceMotion)
            BrandMark(style: .splash, color: RYColor.onAccent)
                .opacity(logoVisible ? 1 : 0)
                .scaleEffect(logoVisible ? 1 : 0.94)
                .blur(radius: logoVisible ? 0 : 6)
        }
        .ignoresSafeArea()
        .task { withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 1.0)) { logoVisible = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("рядом")
        .accessibilityIdentifier("splash")
    }
}

/// Плавно «перетекающий» цветовой градиент. Сетка 3×3 из системного `MeshGradient`: точки медленно
/// смещаются, цвета берутся из токенов (тёмно-синий, акцентный, голубой). Для «Уменьшить движение» — статичный кадр.
struct SplashBackground: View {
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            MeshGradient(width: 3, height: 3,
                         points: Self.points(at: animated ? context.date.timeIntervalSinceReferenceDate : 0),
                         colors: Self.colors,
                         smoothsColors: true)
        }
        .background(RYColor.accentFill)
    }

    private static let colors: [Color] = {
        let ink = RYToken.color("surface-accent-ink")
        let primary = RYColor.accentFill
        let light = RYColor.accent
        let sky = RYToken.Palette.skyBlue.strong
        return [
            ink, primary, light,
            primary, sky, primary,
            ink, primary, light,
        ]
    }()

    /// Углы закреплены, остальные точки плывут по медленным синусоидам с разными фазами.
    static func points(at t: TimeInterval) -> [SIMD2<Float>] {
        func wave(_ speed: Double, _ phase: Double, _ amplitude: Double) -> Float {
            Float(sin(t * speed + phase) * amplitude)
        }
        return [
            SIMD2(0, 0), SIMD2(0.5 + wave(0.7, 0, 0.08), 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + wave(0.5, 1, 0.10)),
            SIMD2(0.5 + wave(0.6, 2, 0.14), 0.5 + wave(0.45, 4, 0.14)),
            SIMD2(1, 0.5 + wave(0.55, 3, 0.10)),
            SIMD2(0, 1), SIMD2(0.5 + wave(0.65, 5, 0.08), 1), SIMD2(1, 1),
        ]
    }
}
