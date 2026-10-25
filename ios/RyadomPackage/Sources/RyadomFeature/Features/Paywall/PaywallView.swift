import SwiftUI
import SwiftData

/// Что именно упёрлось в лимит. Эта строка в сравнении тарифов подсвечивается.
enum PaywallReason: String, Identifiable, Hashable {
    case members, recurringTasks, shoppingLists, documents, general
    var id: String { rawValue }

    var headline: String {
        switch self {
        case .members: "Больше участников в семье"
        case .recurringTasks: "Повторяющиеся дела"
        case .shoppingLists: "Вся история покупок"
        case .documents: "Больше места для документов"
        case .general: "Всё для вашей семьи"
        }
    }
}

/// Строка сравнения тарифов.
struct PlusFeature: Identifiable {
    let reason: PaywallReason
    let systemImage: String
    let title: String
    let free: String
    let plus: String
    var id: String { reason.rawValue }

    static let all: [PlusFeature] = [
        PlusFeature(reason: .members, systemImage: "person.2", title: "Участники", free: "до 3", plus: "до 8"),
        PlusFeature(reason: .recurringTasks, systemImage: "repeat", title: "Повторы дел", free: "нет", plus: "есть"),
        PlusFeature(reason: .shoppingLists, systemImage: "basket", title: "История покупок", free: "30 дней", plus: "вся"),
        PlusFeature(reason: .documents, systemImage: "folder", title: "Документы", free: "100 МБ", plus: "10 ГБ"),
    ]
}

/// Пейвол HomeFold Plus: сравнение тарифов, выбор «год / месяц», покупка и восстановление.
struct PaywallView: View {
    let reason: PaywallReason

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var families: [FamilyRecord]
    @Query(filter: #Predicate<MemberRecord> { !$0.isInvited }) private var members: [MemberRecord]

    @State private var selectedId = PlusProduct.yearly
    @State private var purchased = false

    private var store: SubscriptionStore { session.subscription }
    private var me: MemberRecord? { members.first { $0.id == session.userId } }
    private var isAdmin: Bool { me?.isAdmin == true }
    private var adminName: String? { members.first(where: \.isAdmin)?.displayName }
    private var selectedPlan: PlusPlan? { store.plans.first { $0.id == selectedId } ?? store.plans.first }
    private var isBusy: Bool { store.phase == .purchasing || store.phase == .restoring }

    var body: some View {
        ZStack {
            SplashBackground(config: SplashShaderConfig(kind: .linear, angle: 38, offset: 0.2), animated: !reduceMotion)
                .ignoresSafeArea()
            if purchased {
                success
            } else {
                content
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .interactiveDismissDisabled(store.phase == .purchasing)
        .task { if store.plans.isEmpty { await store.loadPlans() } }
        .sensoryFeedback(.success, trigger: purchased)
    }

    // MARK: Основное содержимое

    private var content: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                comparison
                if isAdmin { planPicker } else { notAdminNotice }
                if let message = store.errorMessage { errorBanner(message) }
                if isAdmin { purchaseButton }
                footer
            }
            .padding(.horizontal, RYSpacing.screen)
            .padding(.top, 56).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image("BrandLogo", bundle: .module).resizable().scaledToFit().frame(height: 84)
            Text("HomeFold Plus").ryFont(.title).foregroundStyle(RYColor.onAccent)
                .accessibilityAddTraits(.isHeader)
            Text(reason.headline).ryFont(.callout).foregroundStyle(RYColor.onAccent.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var comparison: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer()
                column("Бесплатно", emphasized: false)
                column("Plus", emphasized: true)
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
            ForEach(Array(PlusFeature.all.enumerated()), id: \.element.id) { index, feature in
                if index > 0 { Rectangle().fill(RYColor.onAccent.opacity(0.14)).frame(height: 0.5).padding(.horizontal, 8) }
                featureRow(feature)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 14)
        .background(RYColor.onAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: RYRadius.card))
        .accessibilityIdentifier("paywall.comparison")
    }

    private func column(_ title: String, emphasized: Bool) -> some View {
        Text(title).ryFont(.caption)
            .foregroundStyle(RYColor.onAccent.opacity(emphasized ? 1 : 0.7))
            .frame(width: 84)
    }

    private func featureRow(_ feature: PlusFeature) -> some View {
        let highlighted = feature.reason == reason
        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: feature.systemImage).font(.system(size: 16, weight: .regular))
                    .foregroundStyle(RYColor.onAccent).frame(width: 24)
                Text(feature.title).ryFont(.body).foregroundStyle(RYColor.onAccent)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            Text(feature.free).ryFont(.subhead).foregroundStyle(RYColor.onAccent.opacity(0.7)).frame(width: 84)
            Text(feature.plus).ryFont(.bodyMedium).foregroundStyle(RYColor.onAccent).frame(width: 84)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 8)
        .background(highlighted ? RYColor.onAccent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title): бесплатно \(feature.free), Plus \(feature.plus)")
    }

    // MARK: Тарифы

    @ViewBuilder private var planPicker: some View {
        if store.plans.isEmpty {
            if store.plansFailed {
                VStack(spacing: 10) {
                    Text("Не удалось загрузить тарифы").ryFont(.callout).foregroundStyle(RYColor.onAccent)
                    Button("Повторить") { Task { await store.loadPlans() } }
                        .ryFont(.headline).foregroundStyle(RYColor.onAccent)
                        .accessibilityIdentifier("paywall.retry")
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ProgressView().tint(RYColor.onAccent).frame(maxWidth: .infinity, minHeight: 110)
            }
        } else {
            HStack(spacing: 12) {
                ForEach(store.plans) { plan in planCard(plan) }
            }
        }
    }

    private func planCard(_ plan: PlusPlan) -> some View {
        let selected = plan.id == selectedPlan?.id
        let ink = selected ? RYColor.accent : RYColor.onAccent
        return Button {
            withAnimation(reduceMotion ? nil : RYMotion.snappy) { selectedId = plan.id }
        } label: {
            VStack(spacing: 6) {
                Text(plan.title).ryFont(.headline).foregroundStyle(ink)
                Text(plan.displayPrice).ryFont(.heading).foregroundStyle(ink).minimumScaleFactor(0.8).lineLimit(1)
                Text(plan.isYearly ? "≈ \(PlusPricing.monthlyEquivalent(of: plan)) в месяц" : "в месяц")
                    .ryFont(.caption).foregroundStyle(ink.opacity(0.75))
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(selected ? RYColor.onAccent : RYColor.onAccent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: RYRadius.card))
            .overlay(alignment: .top) {
                if plan.isYearly, let percent = store.savingsPercent {
                    Text("−\(percent)%").ryFont(.caption).foregroundStyle(RYColor.onAccent)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(RYColor.accentFill, in: Capsule())
                        .overlay(Capsule().stroke(RYColor.onAccent, lineWidth: 1.5))
                        .offset(y: -11)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("\(plan.title), \(plan.displayPrice)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("paywall.plan.\(plan.isYearly ? "yearly" : "monthly")")
    }

    private var notAdminNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.badge.key").font(.system(size: 22, weight: .light))
            Text("Подписку оформляет администратор семьи").ryFont(.headline).multilineTextAlignment(.center)
            if let adminName {
                Text("Попросите \(adminName) подключить HomeFold Plus — тариф будет действовать для всех участников.")
                    .ryFont(.subhead).multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(RYColor.onAccent)
        .padding(16).frame(maxWidth: .infinity)
        .background(RYColor.onAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: RYRadius.card))
        .accessibilityIdentifier("paywall.notAdmin")
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text).ryFont(.subhead).foregroundStyle(RYColor.onAccent).multilineTextAlignment(.center)
            .padding(12).frame(maxWidth: .infinity)
            .background(RYColor.danger.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("paywall.error")
    }

    // MARK: Кнопки

    private var purchaseButton: some View {
        Button(action: buy) {
            Group {
                if store.phase == .purchasing {
                    ProgressView().tint(RYColor.accent)
                } else if let plan = selectedPlan {
                    Text("Подключить Plus · \(plan.displayPrice) \(plan.isYearly ? "в год" : "в месяц")")
                } else {
                    Text("Подключить Plus")
                }
            }
            .ryFont(.headline).foregroundStyle(RYColor.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(RYColor.onAccent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedPlan == nil || isBusy)
        .opacity(selectedPlan == nil ? 0.5 : 1)
        .accessibilityIdentifier("paywall.purchase")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button { Task { await restore() } } label: {
                if store.phase == .restoring { ProgressView().tint(RYColor.onAccent) } else { Text("Восстановить покупки") }
            }
            .ryFont(.callout).foregroundStyle(RYColor.onAccent)
            .disabled(isBusy)
            .frame(minHeight: 34)
            .accessibilityIdentifier("paywall.restore")
            Text("Оплата списывается с Apple ID при подтверждении. Подписка продлевается автоматически, пока её не отменили в настройках Apple ID не позднее чем за 24 часа до конца периода.")
                .ryFont(.caption).foregroundStyle(RYColor.onAccent.opacity(0.7)).multilineTextAlignment(.center)
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(RYColor.onAccent)
                .frame(width: 34, height: 34).background(RYColor.onAccent.opacity(0.2), in: Circle())
        }
        .padding(.trailing, RYSpacing.screen).padding(.top, 10)
        .disabled(store.phase == .purchasing)
        .accessibilityLabel("Закрыть").accessibilityIdentifier("paywall.close")
    }

    // MARK: Успех

    private var success: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 76)).foregroundStyle(RYColor.onAccent)
                .symbolEffect(.bounce, value: purchased)
            Text("HomeFold Plus подключён").ryFont(.title).foregroundStyle(RYColor.onAccent).multilineTextAlignment(.center)
                .accessibilityIdentifier("paywall.success")
            Text("В семье теперь до 8 участников, дела можно повторять, а для документов — 10 ГБ.")
                .ryFont(.callout).foregroundStyle(RYColor.onAccent.opacity(0.85)).multilineTextAlignment(.center)
            Spacer()
            Button { dismiss() } label: {
                Text("Готово").ryFont(.headline).foregroundStyle(RYColor.accent)
                    .frame(maxWidth: .infinity, minHeight: 52).background(RYColor.onAccent, in: Capsule())
            }
            .buttonStyle(.plain).accessibilityIdentifier("paywall.done")
        }
        .padding(.horizontal, RYSpacing.screen).padding(.bottom, 24)
    }

    // MARK: Действия

    private func buy() {
        guard let plan = selectedPlan else { return }
        Task {
            if await store.purchase(plan) { activate() }
        }
    }

    private func restore() async {
        if await store.restore() { activate() }
    }

    private func activate() {
        session.reconcilePlan(context: context)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { purchased = true }
    }
}

extension View {
    /// Показывает пейвол во весь экран, когда `reason` не nil.
    func paywall(reason: Binding<PaywallReason?>) -> some View {
        fullScreenCover(item: reason) { PaywallView(reason: $0) }
    }
}
