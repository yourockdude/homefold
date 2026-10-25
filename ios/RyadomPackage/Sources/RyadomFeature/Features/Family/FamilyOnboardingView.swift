import SwiftUI
import SwiftData

/// Первый запуск: создание семьи. Показывается, пока в локальной базе нет ни одной семьи.
struct FamilyOnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var myName = ""
    @State private var familyName = ""
    @State private var submitted = false
    @State private var errorText: String?
    @FocusState private var focus: Field?

    private enum Field { case me, family }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandMark().padding(.top, 8)
                ZStack(alignment: .bottomLeading) {
                    FamilyCover()
                    LinearGradient(colors: [RYColor.coverShade.opacity(0.85), RYColor.coverShade.opacity(0)], startPoint: .bottom, endPoint: .top)
                    Text("Меньше забот.\nБольше времени вместе.").ryFont(.headline).foregroundStyle(RYColor.onAccent).padding(18)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: RYRadius.cover))
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Создайте семью").ryFont(.title).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                    Text("Покупки, дела и документы — в одном месте для всех, кто рядом.")
                        .ryFont(.callout).foregroundStyle(RYColor.muted)
                }

                RYTextField("Как вас зовут", text: $myName, placeholder: "Например, Анна",
                            error: submitted && isEmpty(myName) ? "Введите имя" : nil)
                    .focused($focus, equals: .me).submitLabel(.next).onSubmit { focus = .family }
                    .accessibilityIdentifier("onboarding.name")
                RYTextField("Название семьи", text: $familyName, placeholder: "Например, Смирновы",
                            error: submitted && isEmpty(familyName) ? "Введите название" : nil)
                    .focused($focus, equals: .family).submitLabel(.done).onSubmit(create)
                    .accessibilityIdentifier("onboarding.family")

                if let errorText {
                    RYNotice(systemImage: "exclamationmark.triangle", text: errorText, tint: RYColor.danger.opacity(0.12), ink: RYColor.danger)
                }
                Button(action: create) { Text("Создать семью") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("onboarding.create")
                Text("Участников можно пригласить позже — по ссылке.").ryFont(.caption).foregroundStyle(RYColor.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, RYSpacing.screen).padding(.bottom, RYSpacing.l)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(RYColor.background.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: errorText == nil && submitted)
    }

    private func isEmpty(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func create() {
        submitted = true
        guard !isEmpty(myName), !isEmpty(familyName) else { return }
        do {
            try FamilyService(context: context).createFamily(name: familyName, displayName: myName)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
