import SwiftUI
import SwiftData

/// Экран «Дела семьи»: фильтры, лента недели, активные и выполненные дела выбранного дня.
struct TasksView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<TaskOccurrenceRecord> { $0.deletedAt == nil }, sort: \TaskOccurrenceRecord.dueAt)
    private var allTasks: [TaskOccurrenceRecord]
    @Query(sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query private var families: [FamilyRecord]

    @State private var path: [TaskRoute] = []
    @State private var sheet: TaskSheet?
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var filter: TaskFilter = .all
    @State private var showMemberFilter = false
    @State private var memberFilterSelection: UUID?

    private enum Segment: Hashable { case all, mine, members }
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
    /// У каждого участника есть хотя бы одно невыполненное дело на сегодня.
    private var everyoneHasTask: Bool {
        !members.isEmpty && members.allSatisfy { m in
            allTasks.contains { calendar.isDateInToday($0.dueAt) && !$0.isCompleted && $0.assigneeId == m.id }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: TaskRoute.self) { route in
                    switch route {
                    case .detail(let id):
                        TaskDetailView(occurrenceId: id, members: members, familyName: families.first?.name ?? "", path: $path)
                    }
                }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .create(let date): TaskFormView(mode: .create(date), members: members, familyName: families.first?.name ?? "")
            case .edit(let id): TaskFormView(mode: .editOccurrence(id), members: members, familyName: families.first?.name ?? "")
            case .editSeries(let id): TaskFormView(mode: .editSeries(id), members: members, familyName: families.first?.name ?? "")
            }
        }
        .sheet(isPresented: $showMemberFilter) {
            TaskMemberPickerSheet(navTitle: "Участник", heading: "Чьи дела показать?", subtitle: "Выберите участника семьи.",
                                  members: members, currentUserId: session.userId, noneTitle: "Все участники",
                                  selection: $memberFilterSelection) {
                filter = memberFilterSelection.map(TaskFilter.member) ?? .all
            }
        }
    }

    // MARK: Содержимое

    private var content: some View {
        VStack(spacing: 0) {
            RYScreenHeader(title: "Дела семьи", subtitle: "Когда заботы делятся на всех") {
                RYGlassCircleButton(systemImage: "plus", label: "Новое дело") { sheet = .create(defaultStart) }
                    .accessibilityIdentifier("tasks.plus")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.s) {
                    segments
                    WeekStrip(selected: $selectedDay)
                    dayHeader
                    if dayTasks.isEmpty && overdue.isEmpty {
                        emptyDay
                    } else {
                        if !overdue.isEmpty { overdueSection }
                        if !active.isEmpty { activeGroup }
                        if !completed.isEmpty { completedSection }
                        if isToday && filter == .all && everyoneHasTask {
                            RYNotice(systemImage: "person.2", title: "Заботы делятся на всех",
                                     text: "У каждого есть своё дело на сегодня.")
                        }
                    }
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .background(RYColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { sheet = .create(defaultStart) } label: {
                Text(isToday ? "Добавить дело" : "Добавить дело на \(RussianDate.dayMonth(selectedDay))")
            }
            .buttonStyle(.ryPrimary)
            .accessibilityIdentifier("tasks.add")
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, 8)
        }
    }

    private var segments: some View {
        let selection: Segment = { switch filter { case .all: .all; case .mine: .mine; case .member: .members } }()
        return RYSegmentedControl(
            segments: [
                .init(id: Segment.all, title: "Все"),
                .init(id: Segment.mine, title: myCountForDay > 0 ? "Мои · \(myCountForDay)" : "Мои"),
                .init(id: Segment.members, title: memberSegmentTitle),
            ],
            selection: selection
        ) { segment in
            switch segment {
            case .all: filter = .all
            case .mine: filter = .mine
            case .members:
                memberFilterSelection = { if case .member(let id) = filter { id } else { nil } }()
                showMemberFilter = true
            }
        }
        .accessibilityIdentifier("tasks.segments")
    }

    private var memberSegmentTitle: String {
        if case .member(let id) = filter, let m = members.first(where: { $0.id == id }) { return m.displayName }
        return "По участникам"
    }

    private var dayHeader: some View {
        HStack {
            Text(isToday ? "Сегодня, \(RussianDate.dayMonth(selectedDay))" : RussianDate.weekdayDayMonth(selectedDay))
                .ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(active.count) \(OverviewView.plural(active.count, "дело", "дела", "дел"))")
                .ryFont(.body).foregroundStyle(RYColor.accent)
        }
        .padding(.top, 4)
    }

    private var emptyDay: some View {
        VStack(spacing: RYSpacing.m) {
            Image(systemName: "calendar").font(.system(size: 40, weight: .light)).foregroundStyle(RYColor.accent)
                .accessibilityHidden(true).padding(.top, RYSpacing.l)
            Text("День свободен").ryFont(.heading).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            Text("\(RussianDate.onThisWeekday(selectedDay).capitalizedFirst) пока ничего не запланировано. Добавьте дело или выберите другой день.")
                .ryFont(.body).foregroundStyle(RYColor.muted).multilineTextAlignment(.center)
            if !isToday {
                Text("Сегодня, \(RussianDate.dayMonth(.now)), остаются \(todayRemaining) \(OverviewView.plural(todayRemaining, "семейное дело", "семейных дела", "семейных дел")).")
                    .ryFont(.subhead).foregroundStyle(RYColor.muted).multilineTextAlignment(.center).padding(.top, RYSpacing.m)
            }
        }
        .padding(.horizontal, RYSpacing.s)
        .frame(maxWidth: .infinity)
    }

    // MARK: Списки дел

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ПРОСРОЧЕНО").ryFont(.caption).foregroundStyle(RYColor.danger).padding(.leading, 4)
                .accessibilityLabel("Просрочено").accessibilityAddTraits(.isHeader)
            group(overdue, overdueStyle: true)
        }
    }

    private var activeGroup: some View { group(active) }

    private func group(_ tasks: [TaskOccurrenceRecord], overdueStyle: Bool = false) -> some View {
        RYListGroup {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                row(task, overdueStyle: overdueStyle)
                if index < tasks.count - 1 { RYListDivider(inset: 38) }
            }
        }
    }

    private func row(_ task: TaskOccurrenceRecord, overdueStyle: Bool) -> some View {
        let late = overdueStyle || (service?.isOverdue(task) ?? false)
        return HStack(spacing: 12) {
            Button { withAnimation { toggle(task) } } label: {
                RYCheckbox(isOn: task.isCompleted).frame(minWidth: 34, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Вернуть в работу: \(task.title)" : "Отметить выполненным: \(task.title)")
            .accessibilityIdentifier("task.check.\(task.title)")
            Button { path.append(.detail(task.id)) } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).ryFont(.body).foregroundStyle(RYColor.ink).multilineTextAlignment(.leading)
                        Text(subtitle(task)).ryFont(.subhead).foregroundStyle(late ? RYColor.danger : RYColor.muted)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    if task.syncStatus == .pending {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11)).foregroundStyle(RYColor.muted)
                            .accessibilityLabel("Ожидает синхронизации")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открыть дело")
        }
        .padding(.vertical, 8)
        .frame(minHeight: 62)
    }

    /// «18:30 · Дети · Михаил»
    private func subtitle(_ task: TaskOccurrenceRecord) -> String {
        var parts = [task.hasTime ? RussianDate.time(task.dueAt) : "В течение дня"]
        if !task.tag.isEmpty { parts.append(task.tag) }
        if let name = members.first(where: { $0.id == task.assigneeId })?.displayName { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ВЫПОЛНЕНО · \(completed.count)").ryFont(.caption).foregroundStyle(RYColor.muted).padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            RYListGroup {
                ForEach(Array(completed.enumerated()), id: \.element.id) { index, task in
                    completedRow(task)
                    if index < completed.count - 1 { RYListDivider(inset: 38) }
                }
            }
        }
        .padding(.top, 4)
    }

    private func completedRow(_ task: TaskOccurrenceRecord) -> some View {
        HStack(spacing: 12) {
            Button { withAnimation { toggle(task) } } label: { RYCheckbox(isOn: true).frame(minWidth: 34, minHeight: 44) }
                .buttonStyle(.plain)
                .accessibilityLabel("Вернуть в работу: \(task.title)")
            Button { path.append(.detail(task.id)) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).ryFont(.body).strikethrough().foregroundStyle(RYColor.muted).multilineTextAlignment(.leading)
                    Text(completionLine(task)).ryFont(.subhead).foregroundStyle(RYColor.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 62)
    }

    private func completionLine(_ task: TaskOccurrenceRecord) -> String {
        let who = members.first { $0.id == task.completedById }?.displayName ?? "Кто-то"
        let time = task.completedAt.map { RussianDate.time($0) } ?? ""
        return "Выполнено · \(who), \(time)"
    }

    // MARK: Действия

    private var defaultStart: Date {
        if isToday {
            return calendar.date(bySetting: .minute, value: 0, of: Date.now.addingTimeInterval(3600)) ?? .now
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
