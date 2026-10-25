import SwiftUI

/// Логотип HomeFold: объёмный синий дом и название Helvetica Neue. На сплэше — крупный, название белое.
struct BrandMark: View {
    enum Style { case compact, splash }

    var style: Style = .compact
    var color: Color = RYColor.accent

    var body: some View {
        Group {
            if style == .splash {
                VStack(spacing: 14) {
                    house(height: 128)
                    wordmark(size: 40)
                }
            } else {
                HStack(spacing: 6) {
                    house(height: 30)
                    wordmark(size: 24)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HomeFold")
    }

    private func house(height: CGFloat) -> some View {
        Image("BrandLogo", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(height: height)
    }

    private func wordmark(size: CGFloat) -> some View {
        Text("HomeFold")
            .font(.custom("HelveticaNeue-Bold", size: size, relativeTo: .title2))
            .tracking(-size * 0.02)
            .foregroundStyle(color)
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
