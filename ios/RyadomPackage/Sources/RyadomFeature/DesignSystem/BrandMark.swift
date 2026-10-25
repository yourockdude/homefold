import SwiftUI

/// Росток из логотипа «рядом»: два листа на одном побеге (контур из макета, 22 × 15,3).
struct SproutShape: Shape {
    private static let d = "M13.75 9.07762V5.55556C13.75 4.08213 14.3295 2.66905 15.3609 1.62718C16.3924 0.585316 17.7913 0 19.25 0H21.3125C21.4948 0 21.6697 0.0731646 21.7986 0.203398C21.9276 0.333632 22 0.510266 22 0.694444V2.77778C22 4.2512 21.4205 5.66428 20.3891 6.70615C19.3576 7.74802 17.9587 8.33333 16.5 8.33333C15.5262 8.33333 14.579 8.5942 13.75 9.07762C13.3372 9.31832 12.9538 9.6142 12.6109 9.96052C11.5795 11.0024 11 12.4155 11 13.8889C9.97858 14.6627 8.76402 15.1339 7.49241 15.2497C6.2208 15.3655 4.94238 15.1214 3.80041 14.5446C2.65843 13.9679 1.69801 13.0813 1.02678 11.9842C0.355538 10.8872 0 9.623 0 8.33334C1.02142 7.55954 2.23598 7.08833 3.50759 6.97251C4.7792 6.85669 6.05762 7.10084 7.19959 7.67759C8.34157 8.25435 9.30199 9.14093 9.97322 10.238C10.6445 11.335 11 12.5992 11 13.8889C11 12.4155 11.5795 11.0024 12.6109 9.96052C12.9538 9.6142 13.3372 9.31832 13.75 9.07762Z"

    func path(in rect: CGRect) -> Path {
        let source = SVGPath.parse(Self.d)
        let box = CGRect(x: 0, y: 0, width: 22, height: 15.3)
        let scale = min(rect.width / box.width, rect.height / box.height)
        return source.applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Минимальный разбор SVG-контуров (абсолютные команды M, L, H, V, C, Z).
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var tokens: [String] = []
        var number = ""
        func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
        for ch in d {
            if ch.isLetter { flush(); tokens.append(String(ch)) }
            else if ch == " " || ch == "," { flush() }
            else if ch == "-" { flush(); number = "-" }
            else { number.append(ch) }
        }
        flush()

        var path = Path()
        var i = 0
        var command = ""
        var current = CGPoint.zero
        func value() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if tokens[i].first?.isLetter == true { command = tokens[i]; i += 1 }
            switch command {
            case "M": current = CGPoint(x: value(), y: value()); path.move(to: current); command = "L"
            case "L": current = CGPoint(x: value(), y: value()); path.addLine(to: current)
            case "H": current.x = value(); path.addLine(to: current)
            case "V": current.y = value(); path.addLine(to: current)
            case "C":
                let c1 = CGPoint(x: value(), y: value()), c2 = CGPoint(x: value(), y: value())
                current = CGPoint(x: value(), y: value())
                path.addCurve(to: current, control1: c1, control2: c2)
            case "Z": path.closeSubpath()
            default: i += 1
            }
        }
        return path
    }
}

/// Логотип: росток + слово «рядом». На сплэше — крупный и белый.
struct BrandMark: View {
    enum Style { case compact, splash }

    var style: Style = .compact
    var color: Color = RYColor.accent

    var body: some View {
        let scale: CGFloat = style == .splash ? 1.9 : 1
        HStack(spacing: 7 * scale) {
            SproutShape()
                .stroke(color, style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round))
                .frame(width: 22 * scale, height: 15.3 * scale)
                .offset(y: -3 * scale)
            Text("рядом").ryFont(style == .splash ? RYType.h1B : RYType.h3B).foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("рядом")
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
