import SwiftUI
import SwiftData

/// Карточка дела: обычное, просроченное (с переносом срока) и выполненное состояния.
struct TaskDetailView: View {
    let occurrenceId: UUID
    let members: [MemberRecord]
    let familyName: String
    @Binding var path: [TaskRoute]

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @Query private var matches: [TaskOccurrenceRecord]
    @Query private var items: [ChecklistItemRecord]
    @Query private var allSeries: [TaskSeriesRecord]

    @State private var rescheduling: Bool?
    @State private var rescheduleDate = Date.now
    @State private var confirmDelete = false
    @State private var showAssigneeSheet = false
    @State private var assigneeSelection: UUID?
    @State private var sheet: TaskSheet?
    @State private var newItem = ""

    private let calendar = Calendar.current

    init(occurrenceId: UUID, members: [MemberRecord], familyName: String, path: Binding<[TaskRoute]>) {
        self.occurrenceId = occurrenceId
        self.members = members
        self.familyName = familyName
        self._path = path
        _matches = Query(filter: #Predicate<TaskOccurrenceRecord> { $0.id == occurrenceId })
        _items = Query(filter: #Predicate<ChecklistItemRecord> { $0.occurrenceId == occurrenceId && $0.deletedAt == nil },
                       sort: \ChecklistItemRecord.position)
    }

    private var service: TaskService? { session.taskService(context: context) }
    private var task: TaskOccurrenceRecord? { matches.first.flatMap { $0.deletedAt == nil ? $0 : nil } }
    private var series: TaskSeriesRecord? { allSeries.first { $0.id == task?.seriesId } }
    private var isRecurring: Bool { (series?.recurrence ?? .none) != .none }
    private var assignee: MemberRecord? { members.first { $0.id == task?.assigneeId } }
    private var overdue: Bool { task.map { service?.isOverdue($0) ?? false } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            if let task {
                topBar(task)
                ScrollView {
                    VStack(alignment: .leading, spacing: RYSpacing.s) {
                        statusLabel(task)
                        Text(task.title).ryFont(.title).foregroundStyle(RYColor.ink)
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        if task.isCompleted { completionNotice(task) }
                        infoGroup(task)
                        if isRescheduling(task) { reschedulePanel(task) }
                        checklistSection(task)
                        if !task.note.isEmpty && !task.isCompleted { noteBlock(task) }
                        if task.isCompleted {
                            Text("Если вернуть дело в работу, оно снова появится среди дел на этот день.")
                                .ryFont(.callout).foregroundStyle(RYColor.muted)
                        }
                    }
                    .padding(.horizontal, RYSpacing.screen)
                    .padding(.bottom, RYSpacing.m)
                }
                .scrollIndicators(.hidden)
            } else {
                // Дело удалили на другом устройстве, пока карточка была открыта.
                Spacer()
                RYEmptyState(systemImage: "trash", title: "Дела больше нет", message: "Его удалил другой участник семьи.",
                             actionTitle: "К делам семьи") { close() }
                Spacer()
            }
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { if let task { bottomBar(task) } }
        .ryConfirm(isPresented: $confirmDelete, title: "Удалить семейное дело?", message: deleteMessage,
                   confirmTitle: isRecurring ? "Удалить только это дело" : "Удалить дело",
                   extraTitle: isRecurring ? "Удалить всю серию" : nil,
                   onExtra: isRecurring ? { if let task { service?.deleteSeries(task.seriesId); close() } } : nil) {
            if let task { service?.delete(task); close() }
        }
        .sheet(isPresented: $showAssigneeSheet) {
            TaskMemberPickerSheet(navTitle: "Ответственный", heading: "Кто возьмёт дело?", subtitle: pickerSubtitle,
                                  members: members, currentUserId: session.userId, selection: $assigneeSelection) {
                guard let task, assigneeSelection != task.assigneeId else { return }
                var draft = TaskDraft(occurrence: task, recurrence: series?.recurrence ?? .none)
                draft.assigneeId = assigneeSelection
                service?.update(task, with: draft)
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .create(let date): TaskFormView(mode: .create(date), members: members, familyName: familyName)
            case .edit(let id): TaskFormView(mode: .editOccurrence(id), members: members, familyName: familyName)
            case .editSeries(let id): TaskFormView(mode: .editSeries(id), members: members, familyName: familyName)
            }
        }
    }

    // MARK: Вычисляемое

    private func isRescheduling(_ task: TaskOccurrenceRecord) -> Bool {
        guard !task.isCompleted else { return false }
        return rescheduling ?? overdue
    }

    private var pickerSubtitle: String {
        guard let task else { return "Выберите одного участника семьи." }
        let when = task.hasTime ? "\(RussianDate.dayMonth(task.dueAt)), \(RussianDate.time(task.dueAt))" : RussianDate.dayMonth(task.dueAt)
        return "\(task.title) · \(when)\nВыберите одного участника семьи."
    }

    private var deleteMessage: String {
        let name = task?.title ?? ""
        let who = assignee.map { "\(RussianNames.dative($0.displayName)) больше не придёт напоминание" } ?? "Напоминания больше не придут"
        if isRecurring {
            return "«\(name)» повторяется. Можно удалить только это дело или всю серию вместе с историей. \(who). Это нельзя отменить."
        }
        return "«\(name)» исчезнет у всей семьи вместе с чек-листом и комментарием. \(who). Это нельзя отменить."
    }

    // MARK: Верх

    private func topBar(_ task: TaskOccurrenceRecord) -> some View {
        HStack(spacing: RYSpacing.s) {
            RYBackButton("Дела", action: close)
            Spacer()
            Menu {
                Button { sheet = .edit(task.id) } label: { Label("Редактировать", systemImage: "pencil") }
                if !task.isCompleted {
                    Button { rescheduling = true; prepareReschedule(task) } label: { Label("Перенести", systemImage: "calendar.badge.clock") }
                }
                if isRecurring {
                    Button { sheet = .editSeries(task.id) } label: { Label("Изменить всю серию", systemImage: "repeat") }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить", systemImage: "trash") }
            } label: {
                RYGlassCircleLabel(systemImage: "ellipsis")
            }
            .accessibilityLabel("Действия с делом")
            .accessibilityIdentifier("task.menu")
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 4)
    }

    private func statusLabel(_ task: TaskOccurrenceRecord) -> some View {
        let label: String
        let color: Color
        if task.isCompleted {
            label = "Выполнено"; color = RYColor.accent
        } else if overdue {
            label = "Просрочено · \(sinceText(task.dueAt))"; color = RYColor.danger
        } else {
            label = [task.tag, TaskFormView.relativeDay(task.dueAt, calendar: calendar)].filter { !$0.isEmpty }.joined(separator: " · ")
            color = RYColor.peachInk
        }
        return Text(label.uppercased()).ryFont(.subhead).fontWeight(.semibold).foregroundStyle(color)
            .accessibilityLabel(label)
            .accessibilityIdentifier("task.status")
    }

    private func sinceText(_ date: Date) -> String {
        calendar.isDateInYesterday(date) ? "со вчера" : "с \(RussianDate.dayMonth(date))"
    }

    // MARK: Карточки

    private func completionNotice(_ task: TaskOccurrenceRecord) -> some View {
        let who = members.first { $0.id == task.completedById }?.displayName ?? "Участник семьи"
        let at = task.completedAt ?? .now
        return RYNotice(systemImage: "checkmark.circle", title: "Выполнено · \(who), \(RussianDate.time(at))",
                        text: "\(TaskFormView.relativeDay(at, calendar: calendar).capitalizedFirst), \(RussianDate.dayMonth(at)) \(calendar.component(.year, from: at))")
            .accessibilityIdentifier("task.completion")
    }

    private func infoGroup(_ task: TaskOccurrenceRecord) -> some View {
        RYListGroup {
            HStack(spacing: 12) {
                if let assignee { AvatarView(name: assignee.displayName, tone: assignee.tone, diameter: 32) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(assignee?.displayName ?? "Любой участник").ryFont(.body).foregroundStyle(RYColor.ink)
                    Text("Ответственный").ryFont(.subhead).foregroundStyle(RYColor.muted)
                }
                Spacer()
                if !task.isCompleted {
                    Button("Изменить") { assigneeSelection = task.assigneeId; showAssigneeSheet = true }
                        .ryFont(.callout).foregroundStyle(RYColor.accent).accessibilityIdentifier("task.changeAssignee")
                }
            }
            .padding(.vertical, 10).frame(minHeight: 62)
            RYListDivider()
            infoRow(icon: "calendar", primary: dateLine(task), secondary: dateCaption(task))
            if !task.place.isEmpty {
                let lines = task.place.split(separator: "\n", maxSplits: 1).map(String.init)
                RYListDivider()
                infoRow(icon: "mappin.and.ellipse", primary: lines.first ?? task.place, secondary: lines.count > 1 ? lines[1] : nil)
            }
        }
    }

    private func infoRow(icon: String, primary: String, secondary: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(primary).ryFont(.body).foregroundStyle(RYColor.ink)
                if let secondary {
                    Text(secondary).ryFont(.subhead).foregroundStyle(overdue && icon == "calendar" ? RYColor.danger : RYColor.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10).frame(minHeight: 62)
        .accessibilityElement(children: .combine)
    }

    private func dateLine(_ task: TaskOccurrenceRecord) -> String {
        let day = RussianDate.dayMonth(task.dueAt)
        return task.hasTime ? "\(day) · \(RussianDate.time(task.dueAt))" : day
    }

    private func dateCaption(_ task: TaskOccurrenceRecord) -> String? {
        if task.isCompleted {
            let tag = task.tag.isEmpty ? "" : "\(task.tag) · "
            return tag + (series?.recurrence.title(for: task.dueAt).lowercasedFirst ?? "без повторения")
        }
        if overdue { return "Срок пропущен · дело не выполнено" }
        if isRecurring, let r = series?.recurrence { return r.title(for: task.dueAt) }
        guard task.hasTime else { return "Без времени" }
        guard let minutes = task.reminderMinutes else { return "Без напоминания" }
        return minutes == 0 ? "Напомнить в момент срока" : "Напомнить за \(TaskFormView.minutesText(minutes))"
    }

    // MARK: Перенос срока

    private func reschedulePanel(_ task: TaskOccurrenceRecord) -> some View {
        VStack(alignment: .leading, spacing: RYSpacing.s) {
            RYNotice(systemImage: "clock", title: "Выберите новый срок",
                     text: "Перенос не отметит дело выполненным. \(assignee?.displayName ?? "Исполнитель") получит обновлённое напоминание.",
                     tint: RYColor.peach, ink: RYColor.peachInk)
            RYListGroup {
                RYValueRow(title: "Дата") {
                    RYDateField(label: "Новая дата", value: RussianDate.dayMonth(rescheduleDate), date: $rescheduleDate,
                                components: .date, identifier: "reschedule.date", inline: true)
                }
                if task.hasTime {
                    RYListDivider()
                    RYValueRow(title: "Время") {
                        RYDateField(label: "Новое время", value: RussianDate.time(rescheduleDate), date: $rescheduleDate,
                                    components: .hourAndMinute, identifier: "reschedule.time", inline: true)
                    }
                }
            }
            if task.hasTime, let minutes = task.reminderMinutes {
                let fire = rescheduleDate.addingTimeInterval(-TimeInterval(minutes) * 60)
                Text("Напомнить за \(TaskFormView.minutesText(minutes)) · \(TaskFormView.relativeDay(fire, calendar: calendar)) в \(RussianDate.time(fire))")
                    .ryFont(.subhead).foregroundStyle(RYColor.muted)
            }
        }
        .onAppear { if rescheduling == nil { prepareReschedule(task) } }
    }

    private func prepareReschedule(_ task: TaskOccurrenceRecord) {
        var candidate = task.dueAt
        if task.hasTime {
            let t = calendar.dateComponents([.hour, .minute], from: task.dueAt)
            candidate = calendar.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: .now) ?? .now
            if candidate <= .now { candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate }
        } else {
            candidate = calendar.startOfDay(for: .now)
        }
        rescheduleDate = candidate
    }

    // MARK: Чек-лист и заметка

    @ViewBuilder
    private func checklistSection(_ task: TaskOccurrenceRecord) -> some View {
        let done = items.filter(\.isDone).count
        if !items.isEmpty || (!task.isCompleted && !isRescheduling(task)) {
            HStack {
                Text(task.isCompleted ? "Всё готово" : "Не забыть").ryFont(.section).foregroundStyle(RYColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !items.isEmpty && !task.isCompleted { Text("\(done) из \(items.count)").ryFont(.callout).foregroundStyle(RYColor.muted) }
            }
            .padding(.top, 4)
            RYListGroup {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Button { service?.toggle(item) } label: { RYCheckbox(isOn: item.isDone).frame(minWidth: 34, minHeight: 44) }
                            .buttonStyle(.plain)
                            .allowsHitTesting(!task.isCompleted)
                            .accessibilityLabel(item.title)
                            .accessibilityValue(item.isDone ? "выполнено" : "не выполнено")
                        Text(item.title).ryFont(.body).foregroundStyle(item.isDone ? RYColor.muted : RYColor.ink)
                            .strikethrough(item.isDone)
                        Spacer()
                    }
                    .frame(minHeight: 48)
                    .contextMenu {
                        if !task.isCompleted {
                            Button(role: .destructive) { service?.deleteChecklistItem(item) } label: { Label("Удалить пункт", systemImage: "trash") }
                        }
                    }
                    if index < items.count - 1 || !task.isCompleted || (task.isCompleted && !task.note.isEmpty) { RYListDivider(inset: 38) }
                }
                if !task.isCompleted {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 14)).foregroundStyle(RYColor.accent).frame(width: 26, height: 44)
                        TextField("Добавить пункт", text: $newItem).ryFont(.body).foregroundStyle(RYColor.ink)
                            .submitLabel(.done).onSubmit { addItem(task) }
                            .accessibilityIdentifier("task.newItem")
                    }
                    .frame(minHeight: 48)
                } else if !task.note.isEmpty {
                    Text(task.note).ryFont(.body).foregroundStyle(RYColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                }
            }
        }
    }

    private func addItem(_ task: TaskOccurrenceRecord) {
        guard service?.addChecklistItem(newItem, to: task) != nil else { return }
        newItem = ""
    }

    private func noteBlock(_ task: TaskOccurrenceRecord) -> some View {
        let author = members.first { $0.id == task.authorId }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let author { AvatarView(name: author.displayName, tone: author.tone, diameter: 22) }
                Text("\(author?.displayName ?? "Участник") · \(RussianDate.time(task.updatedAt))")
                    .ryFont(.subhead).foregroundStyle(RYColor.muted)
            }
            Text(task.note).ryFont(.body).foregroundStyle(RYColor.ink)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Нижние кнопки

    @ViewBuilder
    private func bottomBar(_ task: TaskOccurrenceRecord) -> some View {
        VStack(spacing: 0) {
            if task.isCompleted {
                Button { service?.reopen(task) } label: { Text("Вернуть в работу") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("task.reopen")
                Button("К делам семьи", action: close).buttonStyle(.ryLink).frame(minHeight: 36)
            } else if isRescheduling(task) {
                Button {
                    service?.reschedule(task, to: rescheduleDate, hasTime: task.hasTime)
                    rescheduling = false
                } label: { Text("Сохранить новый срок") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("task.saveReschedule")
                Button("Отмена переноса") { rescheduling = false }
                    .buttonStyle(.ryLink).frame(minHeight: 36).accessibilityIdentifier("task.cancelReschedule")
            } else {
                Button { service?.complete(task) } label: { Text("Отметить выполненным") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("task.complete")
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 8).padding(.bottom, 4)
    }

    private func close() { if !path.isEmpty { path.removeLast() } }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
