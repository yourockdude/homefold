import SwiftUI
import SwiftData

/// Карточка дела: обычное, просроченное (с переносом срока) и выполненное состояния.
struct TaskDetailView: View {
    let occurrenceId: UUID
    let members: [MemberRecord]
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
    @State private var newItem = ""

    private let calendar = Calendar.current

    init(occurrenceId: UUID, members: [MemberRecord], path: Binding<[TaskRoute]>) {
        self.occurrenceId = occurrenceId
        self.members = members
        self._path = path
        _matches = Query(filter: #Predicate<TaskOccurrenceRecord> { $0.id == occurrenceId })
        _items = Query(filter: #Predicate<ChecklistItemRecord> { $0.occurrenceId == occurrenceId && $0.deletedAt == nil },
                       sort: \ChecklistItemRecord.position)
    }

    private var service: TaskService? { session.taskService(context: context) }
    private var task: TaskOccurrenceRecord? { matches.first.flatMap { $0.deletedAt == nil ? $0 : nil } }

    var body: some View {
        VStack(spacing: 0) {
            if let task {
                topBar(task)
                ScrollView {
                    VStack(alignment: .leading, spacing: RYSpacing.m) {
                        chip(task)
                        Text(task.title).font(.system(size: 30, weight: .semibold)).foregroundStyle(RYColor.ink)
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        if task.isCompleted { completionCard(task) }
                        infoCard(task)
                        if isRescheduling(task) { reschedulePanel(task) }
                        checklistSection(task)
                        if !task.note.isEmpty { noteBlock(task) }
                        if task.isCompleted {
                            Text("Если вернуть дело в работу, оно снова появится среди дел на этот день.")
                                .ryFont(.caption).foregroundStyle(RYColor.muted)
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
            MemberPickerSheet(title: "Кто возьмёт дело?", subtitle: "Выберите одного участника семьи.",
                              members: members, currentUserId: session.userId, selection: $assigneeSelection) {
                guard let task, assigneeSelection != task.assigneeId else { return }
                var draft = TaskDraft(occurrence: task, recurrence: series?.recurrence ?? .none)
                draft.assigneeId = assigneeSelection
                service?.update(task, with: draft)
            }
        }
    }

    // MARK: Вычисляемое

    private var series: TaskSeriesRecord? { allSeries.first { $0.id == task?.seriesId } }
    private var isRecurring: Bool { (series?.recurrence ?? .none) != .none }
    private var assignee: MemberRecord? { members.first { $0.id == task?.assigneeId } }
    private var overdue: Bool { task.map { service?.isOverdue($0) ?? false } ?? false }

    private func isRescheduling(_ task: TaskOccurrenceRecord) -> Bool {
        guard !task.isCompleted else { return false }
        return rescheduling ?? overdue
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
            Button(action: close) { Image(systemName: "arrow.left").font(.system(size: 18)).foregroundStyle(RYColor.ink) }
                .accessibilityLabel("Назад")
            Text("Семейное дело").ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Button { path.append(.edit(task.id)) } label: { Label("Редактировать", systemImage: "pencil") }
                if !task.isCompleted {
                    Button { rescheduling = true; prepareReschedule(task) } label: { Label("Перенести", systemImage: "calendar.badge.clock") }
                }
                if isRecurring {
                    Button { path.append(.editSeries(task.id)) } label: { Label("Изменить всю серию", systemImage: "repeat") }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(RYColor.ink)
                    .frame(width: 40, height: 40).background(RYColor.surface, in: Circle())
            }
            .accessibilityLabel("Действия с делом")
            .accessibilityIdentifier("task.menu")
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.s)
    }

    private func chip(_ task: TaskOccurrenceRecord) -> some View {
        let label: String
        let fg: Color
        let bg: Color
        if task.isCompleted {
            label = "Выполнено"; fg = RYColor.accent; bg = RYColor.accentTint
        } else if overdue {
            label = "Просрочено · \(sinceText(task.dueAt))"; fg = RYColor.danger; bg = RYColor.dangerTint
        } else {
            label = [task.tag, TaskFormView.relativeDay(task.dueAt, calendar: calendar)].filter { !$0.isEmpty }.joined(separator: " · ")
            fg = RYColor.peachInk; bg = RYColor.peach
        }
        return Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 6).background(bg, in: Capsule())
            .accessibilityIdentifier("task.status")
    }

    private func sinceText(_ date: Date) -> String {
        calendar.isDateInYesterday(date) ? "со вчера" : "с \(RussianDate.dayMonth(date))"
    }

    // MARK: Карточки

    private func completionCard(_ task: TaskOccurrenceRecord) -> some View {
        let who = members.first { $0.id == task.completedById }?.displayName ?? "Участник семьи"
        let at = task.completedAt ?? .now
        return HStack(spacing: RYSpacing.s) {
            Image(systemName: "checkmark.circle").font(.system(size: 20, weight: .light)).foregroundStyle(RYColor.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Выполнено · \(who), \(RussianDate.time(at))").ryFont(.body).fontWeight(.semibold).foregroundStyle(RYColor.ink)
                Text("\(TaskFormView.relativeDay(at, calendar: calendar).capitalizedFirst), \(RussianDate.dayMonth(at)) \(calendar.component(.year, from: at))")
                    .ryFont(.micro).foregroundStyle(RYColor.muted)
            }
            Spacer()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RYColor.accentTint, in: RoundedRectangle(cornerRadius: RYRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("task.completion")
    }

    private func infoCard(_ task: TaskOccurrenceRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: RYSpacing.s) {
                if let assignee { AvatarView(name: assignee.displayName, tone: assignee.tone, diameter: 40) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ответственный").ryFont(.micro).foregroundStyle(RYColor.muted)
                    Text(assignee?.displayName ?? "Любой участник").ryFont(.body).fontWeight(.semibold).foregroundStyle(RYColor.ink)
                }
                Spacer()
                if !task.isCompleted {
                    Button("Изменить") { assigneeSelection = task.assigneeId; showAssigneeSheet = true }
                        .ryFont(.caption).fontWeight(.medium).foregroundStyle(RYColor.accent)
                        .accessibilityIdentifier("task.changeAssignee")
                }
            }
            infoRow(icon: "calendar", primary: dateLine(task), secondary: dateCaption(task))
            if !task.place.isEmpty {
                let lines = task.place.split(separator: "\n", maxSplits: 1).map(String.init)
                infoRow(icon: "mappin.and.ellipse", primary: lines.first ?? task.place, secondary: lines.count > 1 ? lines[1] : nil)
            }
        }
        .padding(RYSpacing.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
    }

    private func infoRow(icon: String, primary: String, secondary: String?) -> some View {
        HStack(alignment: .top, spacing: RYSpacing.s) {
            Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(primary).ryFont(.body).fontWeight(.medium).foregroundStyle(RYColor.ink)
                if let secondary { Text(secondary).ryFont(.micro).foregroundStyle(overdue && icon == "calendar" ? RYColor.danger : RYColor.muted) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dateLine(_ task: TaskOccurrenceRecord) -> String {
        let day = calendar.isDateInToday(task.dueAt)
            ? "Сегодня, \(RussianDate.dayMonth(task.dueAt))" : RussianDate.dayMonth(task.dueAt)
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
            HStack(alignment: .top, spacing: RYSpacing.s) {
                Image(systemName: "clock").font(.system(size: 14)).foregroundStyle(RYColor.peachInk)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Выберите новый срок").ryFont(.caption).fontWeight(.semibold).foregroundStyle(RYColor.peachInk)
                    Text("Перенос не отметит дело выполненным. \(assignee?.displayName ?? "Исполнитель") получит обновлённое напоминание.")
                        .ryFont(.caption).foregroundStyle(RYColor.peachInk)
                }
            }
            .padding(RYSpacing.s + 2).frame(maxWidth: .infinity, alignment: .leading)
            .background(RYColor.peach, in: RoundedRectangle(cornerRadius: RYRadius.card))
            HStack(alignment: .top, spacing: RYSpacing.s) {
                VStack(alignment: .leading, spacing: 6) {
                    RYFieldLabel("Дата")
                    RYDateField(label: "Новая дата", value: RussianDate.dayMonth(rescheduleDate), date: $rescheduleDate,
                                components: .date, identifier: "reschedule.date")
                }
                if task.hasTime {
                    VStack(alignment: .leading, spacing: 6) {
                        RYFieldLabel("Время")
                        RYDateField(label: "Новое время", value: RussianDate.time(rescheduleDate), date: $rescheduleDate,
                                    components: .hourAndMinute, identifier: "reschedule.time")
                    }
                }
            }
            if task.hasTime, let minutes = task.reminderMinutes {
                let fire = rescheduleDate.addingTimeInterval(-TimeInterval(minutes) * 60)
                Text("Напомнить за \(TaskFormView.minutesText(minutes)) · \(TaskFormView.relativeDay(fire, calendar: calendar)) в \(RussianDate.time(fire))")
                    .ryFont(.caption).foregroundStyle(RYColor.muted)
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
        if !items.isEmpty || !task.isCompleted {
            HStack {
                Text(task.isCompleted ? "Всё готово" : "Не забыть").ryFont(.section).foregroundStyle(RYColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !items.isEmpty { Text("\(done) из \(items.count)").ryFont(.caption).foregroundStyle(RYColor.muted) }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Button { service?.toggle(item) } label: {
                            RYCheckbox(isOn: item.isDone).frame(minWidth: 30, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(task.isCompleted)
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item.isDone ? "выполнено" : "не выполнено")
                        Text(item.title).ryFont(.body).foregroundStyle(item.isDone ? RYColor.muted : RYColor.ink)
                            .strikethrough(item.isDone)
                        Spacer()
                    }
                    .contextMenu {
                        if !task.isCompleted {
                            Button(role: .destructive) { service?.deleteChecklistItem(item) } label: { Label("Удалить пункт", systemImage: "trash") }
                        }
                    }
                }
                if !task.isCompleted {
                    HStack(spacing: 12) {
                        Image(systemName: "plus").font(.system(size: 13)).foregroundStyle(RYColor.accent).frame(width: 30, height: 44)
                        TextField("Добавить пункт", text: $newItem).ryFont(.body).foregroundStyle(RYColor.ink)
                            .submitLabel(.done)
                            .onSubmit { addItem(task) }
                            .accessibilityIdentifier("task.newItem")
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
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
                    .ryFont(.micro).foregroundStyle(RYColor.muted)
            }
            Text(task.note).ryFont(.body).foregroundStyle(RYColor.ink)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Нижние кнопки

    @ViewBuilder
    private func bottomBar(_ task: TaskOccurrenceRecord) -> some View {
        VStack(spacing: RYSpacing.xs) {
            if task.isCompleted {
                Button { service?.reopen(task) } label: { Label("Вернуть в работу", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("task.reopen")
                Button("К делам семьи", action: close).ryFont(.bodyMedium).foregroundStyle(RYColor.accent).frame(minHeight: 40)
            } else if isRescheduling(task) {
                Button {
                    service?.reschedule(task, to: rescheduleDate, hasTime: task.hasTime)
                    rescheduling = false
                } label: { Text("Сохранить новый срок") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("task.saveReschedule")
                Button("Отмена переноса") { rescheduling = false }
                    .ryFont(.bodyMedium).foregroundStyle(RYColor.accent).frame(minHeight: 40)
                    .accessibilityIdentifier("task.cancelReschedule")
            } else {
                Button { service?.complete(task) } label: { Label("Отметить выполненным", systemImage: "checkmark") }
                    .buttonStyle(.ryPrimary).accessibilityIdentifier("task.complete")
            }
        }
        .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
        .background(RYColor.background)
    }

    private func close() { if !path.isEmpty { path.removeLast() } }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
