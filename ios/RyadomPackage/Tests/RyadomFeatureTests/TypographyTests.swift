import Testing
import SwiftUI
@testable import RyadomFeature

struct TypographyTests {
    @Test("Значения токенов совпадают с Figma")
    func tokenValues() {
        // (токен, размер, межстрочный, трекинг %)
        let expected: [(RYFontToken, CGFloat, CGFloat, CGFloat)] = [
            (RYType.h0B, 48, 48, -2), (RYType.h1B, 40, 48, -3), (RYType.h1N, 40, 48, -4),
            (RYType.h2B, 32, 36, -4), (RYType.h2N, 32, 36, -2),
            (RYType.h3B, 24, 30, -1.5), (RYType.h3M, 24, 30, -3), (RYType.h4B, 20, 26, -1.5), (RYType.h4N, 20, 26, -1),
            (RYType.bodyLB, 18, 24, -2), (RYType.bodyMN, 16, 20, -1.5), (RYType.bodySN, 14, 16, -1),
            (RYType.bodyXSB, 12, 14, -2), (RYType.bodyXXSM, 10, 12, 0),
            (RYType.textLN, 18, 28, -2), (RYType.textMB, 16, 26, -1.5), (RYType.textSN, 14, 20, -1.5), (RYType.textXSB, 12, 16, -2),
            (RYType.display1B, 128, 144, -3), (RYType.display2B, 88, 88, -2),
        ]
        for (token, size, line, tracking) in expected {
            #expect(token.size == size, "\(token.name): размер")
            #expect(token.lineHeight == line, "\(token.name): межстрочный")
            #expect(token.tracking == tracking, "\(token.name): трекинг")
        }
    }

    @Test("Семейства: Body и Headline — Display, Text — Text")
    func families() {
        #expect(RYType.bodyMB.family == .display)
        #expect(RYType.h2B.family == .display)
        #expect(RYType.textMN.family == .text)
        #expect(RYType.display1N.family == .display)
    }

    @Test("Названия токенов уникальны, их 35")
    func catalogue() {
        #expect(RYType.all.count == 35)
        #expect(Set(RYType.all.map(\.name)).count == RYType.all.count)
    }

    @Test("Трекинг переводится из процентов в пункты: −2 % при 88 pt = −1,76 pt")
    func trackingPoints() {
        #expect(abs(RYType.display2B.trackingPoints(at: 88) - (-1.76)) < 0.0001)
        #expect(RYType.bodyXXSN.trackingPoints(at: 10) == 0)
    }

    @Test("Смысловые стили указывают на токены")
    func semanticMapping() {
        #expect(RYFontStyle.title.token == RYType.h2B)
        #expect(RYFontStyle.section.token == RYType.h4B)
        #expect(RYFontStyle.body.token == RYType.bodyMN)
        #expect(RYFontStyle.headline.token == RYType.bodyMB)
        #expect(RYFontStyle.caption.token == RYType.bodyXSN)
        #expect(RYFontStyle.micro.token == RYType.bodyXXSN)
    }

    @Test("Без файлов SB Sans используется системный шрифт, высота строки считается")
    func fallbackWithoutFontFiles() {
        for token in RYType.all {
            if RYFontResolver.customName(for: token) == nil {
                #expect(RYFontResolver.naturalLineHeight(for: token, size: token.size) > 0)
            }
        }
        #expect(RYFontResolver.customName(for: RYType.bodyMN) == nil || UIFont(name: RYFontResolver.customName(for: RYType.bodyMN)!, size: 12) != nil)
    }
}
