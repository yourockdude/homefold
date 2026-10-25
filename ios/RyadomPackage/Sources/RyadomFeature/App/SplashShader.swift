import SwiftUI

/// Вариант фона сплэша: тип градиента и угол, с которого он «создаётся». Выбирается случайно при каждом запуске.
struct SplashShaderConfig: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// Линейный градиент вдоль направления `angle`.
        case linear
        /// Радиальный градиент, центр которого смещён от середины экрана в направлении `angle`.
        case radial
        /// Плывущая сетка 3×3, повёрнутая на `angle`.
        case mesh
    }

    var kind: Kind
    /// Угол в градусах, 0 ..< 360. 0 — вправо, 90 — вниз.
    var angle: Double
    /// Смещение центра радиального градиента от середины экрана, доли от размера экрана.
    var offset: Double

    /// Случайный вариант. Генератор подставляется в тестах.
    static func random(using generator: inout some RandomNumberGenerator) -> SplashShaderConfig {
        SplashShaderConfig(kind: Kind.allCases.randomElement(using: &generator) ?? .mesh,
                           angle: Double.random(in: 0..<360, using: &generator),
                           offset: Double.random(in: 0.12...0.32, using: &generator))
    }

    static func random() -> SplashShaderConfig {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    /// Для отладки и скриншотов: `-RYSplashShader linear:45` (тип и необязательный угол).
    static var debugOverride: SplashShaderConfig? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-RYSplashShader"), index + 1 < args.count else { return nil }
        let parts = args[index + 1].split(separator: ":")
        guard let kind = parts.first.flatMap({ Kind(rawValue: String($0)) }) else { return nil }
        let angle = parts.dropFirst().first.flatMap { Double($0) } ?? 45
        return SplashShaderConfig(kind: kind, angle: angle, offset: 0.2)
        #else
        return nil
        #endif
    }

    var radians: Double { angle * .pi / 180 }
}

/// Фон сплэша в цветах приложения. Тип градиента и угол берутся из `SplashShaderConfig`; розовое свечение
/// всегда лежит на стороне, куда направлен угол, — как на скате крыши логотипа. Для «Уменьшить движение» — статичный кадр.
struct SplashBackground: View {
    let config: SplashShaderConfig
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { context in
            let t = animated ? context.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { proxy in
                ZStack {
                    RYColor.accentFill
                    layer(size: proxy.size, t: t)
                    glow(size: proxy.size, t: t)
                }
            }
        }
    }

    // MARK: Слои

    @ViewBuilder private func layer(size: CGSize, t: TimeInterval) -> some View {
        switch config.kind {
        case .linear: linear(t: t)
        case .radial: radial(size: size, t: t)
        case .mesh: mesh(size: size, t: t)
        }
    }

    /// Направление медленно покачивается вокруг заданного угла.
    private func linear(t: TimeInterval) -> some View {
        let angle = config.radians + sin(t * 0.35) * 0.18
        let dx = cos(angle) * 0.62, dy = sin(angle) * 0.62
        return LinearGradient(
            stops: [
                .init(color: Palette.ink, location: 0),
                .init(color: Palette.primary, location: 0.36),
                .init(color: Palette.sky, location: 0.54),
                .init(color: Palette.primary, location: 0.78),
                .init(color: Palette.light, location: 1),
            ],
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    /// Центр смещён по углу и «дышит».
    private func radial(size: CGSize, t: TimeInterval) -> some View {
        let r = config.offset + sin(t * 0.5) * 0.04
        let center = UnitPoint(x: 0.5 + cos(config.radians) * r, y: 0.5 + sin(config.radians) * r)
        return RadialGradient(
            stops: [
                .init(color: Palette.sky, location: 0),
                .init(color: Palette.primary, location: 0.5),
                .init(color: Palette.ink, location: 1),
            ],
            center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.9)
    }

    /// Сетка — квадрат со стороной в диагональ экрана: при любом угле поворота закрывает весь экран.
    private func mesh(size: CGSize, t: TimeInterval) -> some View {
        let side = (size.width * size.width + size.height * size.height).squareRoot() * 1.05
        return MeshGradient(width: 3, height: 3, points: Self.points(at: t), colors: Self.meshColors, smoothsColors: true)
            .frame(width: side, height: side)
            .rotationEffect(.degrees(config.angle))
            .position(x: size.width / 2, y: size.height / 2)
    }

    /// Розовое свечение: цвет с логотипа, мягкое пятно у края экрана со стороны угла.
    /// Площадь около 6–8%, как у розового на логотипе. Для сетки свечение уже заложено в её цветах.
    @ViewBuilder private func glow(size: CGSize, t: TimeInterval) -> some View {
        if config.kind != .mesh {
            let reach = 0.62 + sin(t * 0.4) * 0.02
            let center = UnitPoint(x: 0.5 + cos(config.radians) * reach, y: 0.5 + sin(config.radians) * reach)
            RadialGradient(colors: [Palette.pink.opacity(0.85), Palette.pink.opacity(0)],
                           center: center, startRadius: 0, endRadius: max(size.width, size.height) * 0.3)
                .blendMode(.normal)
        }
    }

    // MARK: Цвета

    enum Palette {
        static let ink = RYToken.color("surface-accent-ink")
        static let primary = RYColor.accentFill
        static let light = RYColor.accent
        static let sky = RYToken.Palette.skyBlue.strong
        /// Розовое с ската крыши логотипа (240, 132, 248), смешанное со светлым синим.
        static let pink = Color(red: 240 / 255, green: 132 / 255, blue: 248 / 255)
    }

    static let meshColors: [Color] = {
        let softPink = Palette.light.mix(with: Palette.pink, by: 0.6)
        return [
            Palette.ink, Palette.primary, softPink,
            Palette.primary, Palette.sky, Palette.primary,
            Palette.ink, Palette.primary, Palette.light,
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
