import SwiftUI

/// Готовый логотип-надпись: дом и «HomeFold». У семей с подпиской — вариант с плюсом;
/// `inverse` — белая надпись для тёмных и цветных фонов (сплэш, экран подписки).
/// Размер задаётся высотой: у всех вариантов дом одинаковый.
struct BrandWordmark: View {
    var showsPlus = false
    var inverse = false
    var height: CGFloat = 32

    private var assetName: String {
        if inverse { return "BrandWordmarkInverse" }
        return showsPlus ? "BrandWordmarkPlus" : "BrandWordmark"
    }

    var body: some View {
        Image(assetName, bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(showsPlus ? "HomeFold Plus" : "HomeFold")
    }
}

/// Логотип HomeFold. В шапках — готовая надпись (`BrandWordmark`), на сплэше — её белый вариант.
struct BrandMark: View {
    enum Style { case compact, splash }

    var style: Style = .compact
    var color: Color = RYColor.accent
    /// Подписка HomeFold Plus действует: используется логотип с плюсом.
    var showsPlus = false

    var body: some View {
        Group {
            if style == .splash {
                BrandWordmark(inverse: true, height: 66)
            } else {
                BrandWordmark(showsPlus: showsPlus, height: 34)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsPlus ? "HomeFold Plus" : "HomeFold")
    }
}

/// Фотография обложки семьи из ресурсов; при отсутствии — зелёный градиент.
struct FamilyCover: View {
    private static let image: UIImage? = {
        guard let url = Bundle.module.url(forResource: "FamilyCover", withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    var body: some View {
        GeometryReader { proxy in
            if let image = Self.image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            } else {
                LinearGradient(colors: [RYColor.accent, RYColor.coverShade], startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
    }
}
