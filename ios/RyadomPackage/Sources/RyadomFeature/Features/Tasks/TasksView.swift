import SwiftUI
import SwiftData

/// Экран «Дела семьи»: лента недели, фильтры, активные и выполненные дела выбранного дня.
struct TasksView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<TaskOccurrenceRecord> { $0.deletedAt == nil }, sort: \TaskOccurrenceRecord.dueAt)
    private var allTasks: [TaskOccurrenceRecord]
    @Query(sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query private var families: [FamilyRecord]

    @State private var path: [TaskRoute] = []
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var filter: TaskFilter = .all
    @State private var showMemberFilter = false
    @State private var memberFilterSelection: UUID?
    @State private var completedExpanded = false

    private let calendar = Calendar.current

    private var service: TaskService? { session.taskService(context: context) }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }

    private func matches(_ task: TaskOccurrenceRecord) -> Bool {
        switch filter {
        case .all: true
        case .mine: task.assigneeId == session.userId
        case .member(let id): task.assigneeId == id
        }
    }

    private var dayTasks: [TaskOccurrenceRecord] {
        allTasks.filter { calendar.isDate($0.dueAt, inSameDayAs: selectedDay) && matches($0) }
    }
    private var active: [TaskOccurrenceRecord] { dayTasks.filter { !$0.isCompleted } }
    private var completed: [TaskOccurrenceRecord] { dayTasks.filter(\.isCompleted) }
    /// Просроченные с прошлых дней показываем на «Сегодня».
    private var overdue: [TaskOccurrenceRecord] {
        guard isToday else { return [] }
        let start = calendar.startOfDay(for: .now)
        return allTasks.filter { !$0.isCompleted && $0.dueAt < start && matches($0) }
    }
    private var myCountForDay: Int {
        allTasks.filter { calendar.isDate($0.dueAt, inSameDayAs: selectedDay) && !$0.isCompleted && $0.assigneeId == session.userId }.count
    }
    private var todayRemaining: Int {
        allTasks.filter { calendar.isDateInToday($0.dueAt) && !$0.isCompleted }.count
    }
    private var highlightedId: UUID? {
        guard isToday else { return nil }
        return active.first { $0.hasTime && $0.dueAt >= .now }?.id
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: TaskRoute.self) { route in
                    switch route {
                    case .detail(let id):
                        TaskDetailView(occurrenceId: id, members: members, path: $path)
                    case .create(let date):
                        TaskFormView(mode: .create(date), members: members, familyName: families.first?.name ?? "", path: $path)
                    case .edit(let id):
                        TaskFormView(mode: .editOccurrence(id), members: members, familyName: families.first?.name ?? "", path: $path)
                    case .editSeries(let id):
                        TaskFormView(mode: .editSeries(id), members: members, familyName: families.first?.name ?? "", path: $path)
                    }
                }
        }
        .sheet(isPresented: $showMemberFilter) {
            MemberPickerSheet(title: "Чьи дела показать?", subtitle: "Выберите участника семьи.",
                              members: members, currentUserId: session.userId, noneTitle: "Все участники",
                              selection: $memberFilterSelection) {
                filter = memberFilterSelection.map(TaskFilter.member) ?? .all
            }
        }
    }

    // MARK: Содержимое

    private var content: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.m) {
                    filters
                    WeekStrip(selected: $selectedDay)
                    dayHeader
                    if dayTasks.isEmpty && overdue.isEmpty {
                        emptyDay
                    } else {
                        VStack(spacing: 10) {
                            if !overdue.isEmpty { overdueSection }
                            ForEach(active) { task in card(task) }
                        }
                        if !completed.isEmpty { completedBlock }
                    }
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .background(RYColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { path.append(.create(defaultStart)) } label: {
                Label(isToday ? "Добавить дело" : "Добавить дело на \(RussianDate.dayMonth(selectedDay))", systemImage: "plus")
            }
            .buttonStyle(.ryPrimary)
            .accessibilityIdentifier("tasks.add")
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
            .background(RYColor.background)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: RYSpacing.s) {
                Text("Дела семьи").font(.system(size: 30, weight: .semibold)).foregroundStyle(RYColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { path.append(.create(defaultStart)) } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(RYColor.accent, in: Circle())
                }
                .accessibilityLabel("Новое дело")
                .accessibilityIdentifier("tasks.plus")
            }
            Text("Когда заботы делятся на всех").ryFont(.body).foregroundStyle(RYColor.muted)
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.m)
    }

    private var filters: some View {
        HStack(spacing: 8) {
            chip("Все", selected: filter == .all) { filter = .all }
            chip(myCountForDay > 0 ? "Мои · \(myCountForDay)" : "Мои", selected: filter == .mine) { filter = .mine }
            chip(memberChipTitle, selected: { if case .member = filter { true } else { false } }()) {
                memberFilterSelection = { if case .member(let id) = filter { id } else { nil } }()
                showMemberFilter = true
            }
        }
    }

    private var memberChipTitle: String {
        if case .member(let id) = filter, let m = members.first(where: { $0.id == id }) { return m.displayName }
        return "По участникам"
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ryFont(.caption).fontWeight(.medium)
                .foregroundStyle(selected ? .white : RYColor.muted)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(selected ? RYColor.accent : RYColor.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var dayHeader: some View {
        HStack {
            Text(isToday ? "Сегодня, \(RussianDate.dayMonth(selectedDay))" : RussianDate.weekdayDayMonth(selectedDay))
                .ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(active.count) \(OverviewView.plural(active.count, "дело", "дела", "дел"))")
                .ryFont(.caption).fontWeight(.medium).foregroundStyle(RYColor.accent)
        }
    }

    private var emptyDay: some View {
        VStack(spacing: RYSpacing.l) {
            RYEmptyState(
                systemImage: "calendar",
                title: "День свободен",
                message: "\(RussianDate.onThisWeekday(selectedDay).capitalizedFirst) пока ничего не запланировано. Добавьте дело или выберите другой день.")
            if !isToday {
                Text("Сегодня, \(RussianDate.dayMonth(.now)), остаются \(todayRemaining) \(OverviewView.plural(todayRemaining, "семейное дело", "семейных дела", "семейных дел")).")
                    .ryFont(.micro).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
            }
        }
        .padding(.top, RYSpacing.l)
    }

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Просрочено", systemImage: "exclamationmark.circle")
                .ryFont(.caption).fontWeight(.semibold).foregroundStyle(RYColor.danger)
            ForEach(overdue) { task in card(task, overdueStyle: true) }
        }
    }

    private func card(_ task: TaskOccurrenceRecord, overdueStyle: Bool = false) -> some View {
        TaskCard(task: task, assignee: members.first { $0.id == task.assigneeId },
                 isHighlighted: task.id == highlightedId,
                 isOverdue: overdueStyle || (service?.isOverdue(task) ?? false),
                 onToggle: { withAnimation { toggle(task) } },
                 onOpen: { path.append(.detail(task.id)) })
    }

    private var completedBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(completed.enumerated()), id: \.element.id) { index, task in
                if index == 0 || completedExpanded {
                    HStack(spacing: 12) {
                        Button { withAnimation { toggle(task) } } label: {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(RYColor.accent)
                                .frame(width: 23, height: 23).background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: 8))
                                .frame(minWidth: 30, minHeight: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Вернуть в работу: \(task.title)")
                        Button { path.append(.detail(task.id)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).ryFont(.caption).strikethrough().foregroundStyle(RYColor.muted)
                                Text(completionLine(task, extra: index == 0 && !completedExpanded ? completed.count - 1 : 0))
                                    .ryFont(.micro).foregroundStyle(RYColor.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index == 0 && completed.count > 1 {
                            Button { withAnimation { completedExpanded.toggle() } } label: {
                                Image(systemName: "chevron.down").font(.system(size: 13)).foregroundStyle(RYColor.muted)
                                    .rotationEffect(.degrees(completedExpanded ? 180 : 0)).frame(width: 30, height: 30)
                            }
                            .accessibilityLabel(completedExpanded ? "Свернуть выполненные" : "Показать выполненные")
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
            }
        }
    }

    private func completionLine(_ task: TaskOccurrenceRecord, extra: Int) -> String {
        let who = members.first { $0.id == task.completedById }?.displayName ?? "Кто-то"
        let time = task.completedAt.map { RussianDate.time($0) } ?? ""
        let base = "Выполнено · \(who), \(time)"
        return extra > 0 ? "\(base) · и ещё \(extra)" : base
    }

    // MARK: Действия

    private var defaultStart: Date {
        if isToday {
            let next = calendar.date(bySetting: .minute, value: 0, of: Date.now.addingTimeInterval(3600)) ?? .now
            return next
        }
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: selectedDay) ?? selectedDay
    }

    private func toggle(_ task: TaskOccurrenceRecord) {
        task.isCompleted ? service?.reopen(task) : service?.complete(task)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
