import SwiftUI
import SwiftData

/// Семейный обзор. Все счётчики считаются из локальной базы.
struct OverviewView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    var onOpenTasks: () -> Void
    var onOpenDocuments: () -> Void

    @Query private var families: [FamilyRecord]
    @Query(sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query(filter: #Predicate<ShoppingItemRecord> { !$0.isBought && $0.deletedAt == nil })
    private var unboughtItems: [ShoppingItemRecord]
    @Query(filter: #Predicate<TaskOccurrenceRecord> { $0.deletedAt == nil }, sort: \TaskOccurrenceRecord.dueAt)
    private var occurrences: [TaskOccurrenceRecord]
    @Query(filter: #Predicate<DocumentRecord> { $0.deletedAt == nil && $0.expiresAt != nil }, sort: \DocumentRecord.expiresAt)
    private var expiringDocuments: [DocumentRecord]

    private var todayTasks: [TaskOccurrenceRecord] {
        occurrences.filter { Calendar.current.isDateInToday($0.dueAt) && !$0.isCompleted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: RYSpacing.l) {
                header
                greeting
                cover
                summary
                todaySection
                if let doc = expiringDocuments.first(where: { ($0.expiresAt ?? .distantPast) >= .now }) { documentCard(doc) }
            }
            .padding(.horizontal, RYSpacing.screen)
            .padding(.vertical, RYSpacing.s)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack {
            HStack(spacing: RYSpacing.xs) {
                Image(systemName: "leaf").font(.system(size: 22, weight: .light)).foregroundStyle(RYColor.accent)
                Text("рядом").ryFont(.brand).foregroundStyle(RYColor.ink)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            HStack(spacing: 5) {
                ForEach(members.prefix(4)) { AvatarView(name: $0.displayName, tone: $0.tone) }
            }
        }
        .frame(minHeight: 40)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "ru_RU"))).uppercased())
                .ryFont(.caption).foregroundStyle(RYColor.muted)
            Text("\(Self.greeting(for: .now)), \(members.first?.displayName ?? "")")
                .ryFont(.title).foregroundStyle(RYColor.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            RYColor.accent
            LinearGradient(colors: [RYColor.coverShade.opacity(0.9), RYColor.coverShade.opacity(0)],
                           startPoint: .bottom, endPoint: .top)
            VStack(alignment: .leading, spacing: 5) {
                Text(families.first?.name ?? "").ryFont(.heading).foregroundStyle(.white)
                Text("Меньше забот. Больше времени вместе.").ryFont(.caption).foregroundStyle(.white.opacity(0.87))
            }
            .padding(RYSpacing.l)
        }
        .frame(height: 152)
        .clipShape(RoundedRectangle(cornerRadius: RYRadius.cover))
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        HStack(spacing: RYSpacing.s) {
            summaryTile(title: "Купить", count: unboughtItems.count,
                        unit: Self.plural(unboughtItems.count, "продукт", "продукта", "продуктов"),
                        icon: "basket", bg: RYColor.accentTint, ink: RYColor.accent)
            summaryTile(title: "Сегодня", count: todayTasks.filter { !$0.isCompleted }.count,
                        unit: Self.plural(todayTasks.filter { !$0.isCompleted }.count, "семейное дело", "семейных дела", "семейных дел"),
                        icon: "checkmark.circle", bg: RYColor.peach, ink: RYColor.peachInk)
        }
    }

    private func summaryTile(title: String, count: Int, unit: String, icon: String, bg: Color, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).ryFont(.caption)
                Spacer()
                Image(systemName: icon).font(.system(size: 14, weight: .light))
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(count)").ryFont(.title).foregroundStyle(RYColor.ink)
                Text(unit).ryFont(.micro)
            }
        }
        .foregroundStyle(ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: RYRadius.card))
        .accessibilityElement(children: .combine)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: RYSpacing.s) {
            RYSectionHeader("Сегодня вместе", actionTitle: "Все дела →", action: onOpenTasks)
            if todayTasks.isEmpty {
                RYCard { Text("На сегодня дел нет").ryFont(.body).foregroundStyle(RYColor.muted) }
            } else {
                VStack(spacing: 0) {
                    ForEach(todayTasks.prefix(3)) { task in
                        HStack(spacing: 11) {
                            Button {
                                let service = session.taskService(context: context)
                                task.isCompleted ? service?.reopen(task) : service?.complete(task)
                            } label: { RYCheckbox(isOn: task.isCompleted).frame(minWidth: 30, minHeight: 44) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(task.isCompleted ? "Вернуть в работу: \(task.title)" : "Отметить выполненным: \(task.title)")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).ryFont(.bodyMedium).foregroundStyle(RYColor.ink)
                                if task.hasTime {
                                    Text(task.dueAt.formatted(date: .omitted, time: .shortened)).ryFont(.micro).foregroundStyle(RYColor.muted)
                                }
                            }
                            Spacer()
                            if let m = members.first(where: { $0.id == task.assigneeId }) {
                                AvatarView(name: m.displayName, tone: m.tone, diameter: 28)
                            }
                        }
                        .frame(minHeight: 52)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            }
        }
    }

    private func documentCard(_ doc: DocumentRecord) -> some View {
        Button(action: onOpenDocuments) {
            HStack(spacing: RYSpacing.s) {
                Image(systemName: doc.category.systemImage)
                    .font(.system(size: 18, weight: .light)).foregroundStyle(RYColor.peachInk)
                    .frame(width: 38, height: 42)
                    .background(RYColor.peach, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    Text(doc.title).ryFont(.bodyMedium).foregroundStyle(RYColor.ink)
                    if let d = doc.expiresAt {
                        Text("Действует до \(d.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU"))))")
                            .ryFont(.micro).foregroundStyle(RYColor.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(RYColor.muted)
            }
            .padding(14)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
        }
        .buttonStyle(.plain)
    }

    static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Доброе утро"
        case 12..<18: "Добрый день"
        case 18..<23: "Добрый вечер"
        default: "Доброй ночи"
        }
    }

    /// Русские формы числительных: 1 / 2–4 / 5+.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m100 = n % 100, m10 = n % 10
        if (11...14).contains(m100) { return many }
        switch m10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
