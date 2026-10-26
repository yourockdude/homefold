import SwiftUI

/// Готовый логотип-надпись: дом и «HomeFold». У семей с подпиской — вариант с плюсом.
/// Размер задаётся высотой: у обоих вариантов дом одинаковый.
struct BrandWordmark: View {
    var showsPlus = false
    var height: CGFloat = 32

    var body: some View {
        Image(showsPlus ? "BrandWordmarkPlus" : "BrandWordmark", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(showsPlus ? "HomeFold Plus" : "HomeFold")
    }
}

/// Логотип HomeFold. В шапках — готовая надпись (`BrandWordmark`), на сплэше — дом и белое название.
struct BrandMark: View {
    enum Style { case compact, splash }

    var style: Style = .compact
    var color: Color = RYColor.accent
    /// Подписка HomeFold Plus действует: используется логотип с плюсом.
    var showsPlus = false

    var body: some View {
        Group {
            if style == .splash {
                VStack(spacing: 14) {
                    Image("BrandLogo", bundle: .module).resizable().scaledToFit().frame(height: 128)
                    Text("HomeFold")
                        .font(.custom("HelveticaNeue-Bold", size: 40, relativeTo: .title2))
                        .tracking(-0.8)
                        .foregroundStyle(color)
                }
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
