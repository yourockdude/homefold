import SwiftUI

/// Слайд знакомства с приложением.
struct OnboardingSlide: Identifiable, Equatable {
    let id: Int
    let illustration: RYIllustrationKind
    let title: String
    let text: String

    static let all: [OnboardingSlide] = [
        OnboardingSlide(id: 0, illustration: .basket, title: "Покупки — вся семья в курсе",
                        text: "Общий список: добавляйте товары и отмечайте купленное — изменения сразу видят все. Можно назначить, кто купит."),
        OnboardingSlide(id: 1, illustration: .calendar, title: "Дела без забывчивости",
                        text: "Назначайте ответственного, время, повтор и напоминание. Просроченное не потеряется — его можно перенести."),
        OnboardingSlide(id: 2, illustration: .folder, title: "Документы под рукой",
                        text: "Полисы, паспорта, справки — по категориям. Добавьте фото, скан или файл и находите по названию и владельцу."),
        OnboardingSlide(id: 3, illustration: .lock, title: "Защита Face ID",
                        text: "Документы можно закрыть Face ID. Файлы хранятся в зашифрованном виде, доступ — только у вашей семьи."),
        OnboardingSlide(id: 4, illustration: .cloud, title: "Работает без интернета",
                        text: "Всё сохраняется на телефоне, а изменения отправляются, как только появляется связь. Ничего не потеряется."),
    ]
}

/// Онбординг после первого запуска: слайды с иллюстрациями, «Пропустить» и «Далее / Начать».
struct OnboardingView: View {
    var slides = OnboardingSlide.all
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private var isLast: Bool { page == slides.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                ForEach(slides) { slide in
                    SlidePage(slide: slide).tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            pageDots.padding(.bottom, 22)
            Button(action: advance) { Text(isLast ? "Начать" : "Далее") }
                .buttonStyle(.ryPrimary)
                .accessibilityIdentifier("onboarding.next")
                .padding(.horizontal, RYSpacing.screen).padding(.bottom, 16)
        }
        .background(RYColor.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: page)
    }

    private var topBar: some View {
        HStack {
            BrandMark()
            Spacer()
            if !isLast {
                Button("Пропустить", action: onFinish)
                    .ryFont(.body).foregroundStyle(RYColor.muted)
                    .transition(.opacity)
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 8).frame(minHeight: 44)
        .animation(.easeInOut(duration: 0.2), value: isLast)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(slides) { slide in
                Capsule()
                    .fill(slide.id == page ? RYColor.accentFill : RYColor.divider)
                    .frame(width: slide.id == page ? 22 : 7, height: 7)
            }
        }
        .animation(reduceMotion ? nil : RYMotion.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Страница \(page + 1) из \(slides.count)")
    }

    private func advance() {
        if isLast { onFinish(); return }
        withAnimation(reduceMotion ? nil : RYMotion.smooth) { page += 1 }
    }
}

private struct SlidePage: View {
    let slide: OnboardingSlide

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [RYColor.accentTint, RYColor.accentTint.opacity(0)],
                                         center: .center, startRadius: 10, endRadius: 170))
                    .frame(width: 340, height: 340)
                RYIllustration(slide.illustration, height: 230)
            }
            .frame(height: 300)
            VStack(spacing: 12) {
                Text(slide.title).ryFont(.title).foregroundStyle(RYColor.ink)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Text(slide.text).ryFont(.callout).foregroundStyle(RYColor.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.page.\(slide.id)")
    }
}
