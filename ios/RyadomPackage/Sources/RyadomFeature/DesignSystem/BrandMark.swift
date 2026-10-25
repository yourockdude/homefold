import SwiftUI

/// Логотип HomeFold: объёмный синий дом на скруглённой плитке и слово HomeFold. На сплэше — крупный, слово белое.
struct BrandMark: View {
    enum Style { case compact, splash }

    var style: Style = .compact
    var color: Color = RYColor.accent

    var body: some View {
        Group {
            if style == .splash {
                VStack(spacing: 18) {
                    tile(size: 120)
                    Text("HomeFold").ryFont(RYType.h1B).foregroundStyle(color)
                }
            } else {
                HStack(spacing: 8) {
                    tile(size: 32)
                    Text("HomeFold").ryFont(RYType.h3B).foregroundStyle(color)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HomeFold")
    }

    private func tile(size: CGFloat) -> some View {
        Image("BrandLogo", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
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
