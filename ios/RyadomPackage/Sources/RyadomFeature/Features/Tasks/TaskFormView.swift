import SwiftUI
import SwiftData

/// Создание дела, правка одного выполнения и явная правка серии — модальный лист.
struct TaskFormView: View {
    enum Mode: Hashable {
        case create(Date)
        case editOccurrence(UUID)
        case editSeries(UUID)
    }

    let mode: Mode
    let members: [MemberRecord]
    let familyName: String

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var draft = TaskDraft(start: .now)
    @State private var loaded = false
    @State private var submitted = false
    @State private var showAssigneeSheet = false
    @State private var assigneeSelection: UUID?
    @FocusState private var titleFocused: Bool

    private let calendar = Calendar.current
    private let reminderOptions: [(Int?, String)] = [
        (nil, "Без напоминания"), (0, "В момент срока"), (10, "За 10 минут"),
        (30, "За 30 минут"), (60, "За час"), (1440, "За день"),
    ]
    private let tagOptions = ["", "Дети", "Дом", "Документы", "Здоровье", "Работа"]

    private var service: TaskService? { session.taskService(context: context) }
    private var isCreate: Bool { if case .create = mode { true } else { false } }
    private var isSeriesEdit: Bool { if case .editSeries = mode { true } else { false } }
    private var isEditOccurrence: Bool { if case .editOccurrence = mode { true } else { false } }
    private var screenTitle: String {
        switch mode {
        case .create: "Новое дело"
        case .editOccurrence: "Изменить дело"
        case .editSeries: "Изменить серию"
        }
    }
    private var titleError: String? { submitted && draft.problem == .emptyTitle ? "Введите название дела." : nil }
    private var assignee: MemberRecord? { members.first { $0.id == draft.assigneeId } }

    var body: some View {
        RYSheetScaffold(title: screenTitle, confirmTitle: isCreate ? "Создать" : "Сохранить",
                        confirmIdentifier: "task.submit", onCancel: { dismiss() }, onConfirm: submit) {
            Text("Для семьи \(RussianNames.familyGenitive(familyName))").ryFont(.callout).foregroundStyle(RYColor.muted)
            if isSeriesEdit {
                RYNotice(systemImage: "repeat", text: "Изменения применятся к этому и следующим делам серии. Выполненные и отдельно изменённые дела останутся как были.")
            }
            titleField
            mainGroup
            placeField
            noteField
            if isCreate { checklistField }
            extrasGroup
            reminderNotice
        }
        .sheet(isPresented: $showAssigneeSheet) {
            TaskMemberPickerSheet(navTitle: "Ответственный", heading: "Кто возьмёт дело?", subtitle: pickerSubtitle,
                                  members: members, currentUserId: session.userId, selection: $assigneeSelection) {
                draft.assigneeId = assigneeSelection
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Поля

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Что нужно сделать · обязательно")
            TextField("Например, полить растения", text: $draft.title)
                .focused($titleFocused).ryFont(.body).foregroundStyle(RYColor.ink)
                .ryField(isError: titleError != nil, isFocused: titleFocused)
                .accessibilityIdentifier("task.title")
            if let titleError { Text(titleError).ryFont(.subhead).foregroundStyle(RYColor.danger) }
        }
    }

    private var mainGroup: some View {
        RYListGroup {
            Button {
                assigneeSelection = draft.assigneeId
                showAssigneeSheet = true
            } label: {
                HStack(spacing: 12) {
                    if let assignee { AvatarView(name: assignee.displayName, tone: assignee.tone, diameter: 32) }
                    else { Image(systemName: "person").font(.system(size: 18, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 32) }
                    Text("Ответственный").ryFont(.body).foregroundStyle(RYColor.ink)
                    Spacer(minLength: 8)
                    Text(assignee?.displayName ?? "Выбрать").ryFont(.body).foregroundStyle(RYColor.accent)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task.assignee")
            RYListDivider()
            RYValueRow(title: "Дата", systemImage: "calendar") {
                RYDateField(label: "Дата", value: RussianDate.dayMonth(draft.start), date: dateBinding,
                            components: .date, identifier: "task.date", inline: true)
            }
            RYListDivider()
            RYValueRow(title: "Время", systemImage: "clock") {
                HStack(spacing: 10) {
                    if draft.hasTime {
                        RYDateField(label: "Время", value: RussianDate.time(draft.start), date: timeBinding,
                                    components: .hourAndMinute, identifier: "task.time", inline: true)
                    }
                    Toggle("Указать время", isOn: $draft.hasTime).labelsHidden().tint(RYColor.accent)
                        .accessibilityIdentifier("task.timeToggle")
                        .onChange(of: draft.hasTime) { _, on in if on { applyDefaultTime() } }
                }
            }
            if !isEditOccurrence {
                RYListDivider()
                Menu {
                    Picker("Повторять", selection: $draft.recurrence) {
                        ForEach(Recurrence.allCases, id: \.self) { Text($0.title(for: draft.start)).tag($0) }
                    }
                } label: {
                    RYValueRow(title: "Повторять", subtitle: draft.recurrence.title(for: draft.start), systemImage: "repeat") {
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .medium))
                    }
                }
                .accessibilityIdentifier("task.recurrence")
            }
        }
    }

    private var placeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Место · необязательно")
            TextField("Например, студия «Ритм»", text: $draft.place, axis: .vertical)
                .ryFont(.body).foregroundStyle(RYColor.ink).ryField()
                .accessibilityIdentifier("task.place")
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Заметка · необязательно")
            TextField("Например, на кухне и в гостиной", text: $draft.note, axis: .vertical)
                .ryFont(.body).foregroundStyle(RYColor.ink).ryField()
                .accessibilityIdentifier("task.note")
        }
    }

    private var checklistField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Чек-лист · необязательно")
            RYListGroup {
                ForEach(draft.checklist.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        RYCheckbox(isOn: false)
                        TextField("Пункт", text: $draft.checklist[index]).ryFont(.body).foregroundStyle(RYColor.ink)
                            .accessibilityIdentifier("task.check.\(index)")
                        Button { draft.checklist.remove(at: index) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(RYColor.muted).frame(width: 32, height: 44)
                        }
                        .accessibilityLabel("Удалить пункт")
                    }
                    .frame(minHeight: 48)
                    RYListDivider()
                }
                Button { draft.checklist.append("") } label: {
                    Label("Добавить пункт", systemImage: "plus").ryFont(.body).foregroundStyle(RYColor.accent)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("task.addCheck")
            }
        }
    }

    private var extrasGroup: some View {
        RYListGroup {
            Menu {
                Picker("Напоминание", selection: $draft.reminderMinutes) {
                    ForEach(reminderOptions, id: \.1) { Text($0.1).tag($0.0) }
                }
            } label: {
                RYValueRow(title: "Напоминание", systemImage: "bell") {
                    HStack(spacing: 6) {
                        Text(reminderOptions.first { $0.0 == draft.reminderMinutes }?.1 ?? "Без напоминания")
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .medium))
                    }
                }
            }
            .disabled(!draft.hasTime)
            .opacity(draft.hasTime ? 1 : 0.5)
            .accessibilityIdentifier("task.reminder")
            RYListDivider()
            Menu {
                Picker("Метка", selection: $draft.tag) {
                    ForEach(tagOptions, id: \.self) { Text($0.isEmpty ? "Без метки" : $0).tag($0) }
                }
            } label: {
                RYValueRow(title: "Метка", systemImage: "tag") {
                    HStack(spacing: 6) {
                        Text(draft.tag.isEmpty ? "Без метки" : draft.tag)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .medium))
                    }
                }
            }
            .accessibilityIdentifier("task.tag")
        }
    }

    @ViewBuilder private var reminderNotice: some View {
        if draft.hasTime, let minutes = draft.reminderMinutes {
            let fire = draft.start.addingTimeInterval(-TimeInterval(minutes) * 60)
            let who = assignee.map { RussianNames.dative($0.displayName) } ?? "всем"
            RYNotice(systemImage: "bell",
                     title: minutes == 0 ? "Напомнить в момент срока" : "Напомнить за \(Self.minutesText(minutes))",
                     text: "\(who.capitalizedFirst) \(Self.relativeDay(fire, calendar: calendar)) в \(RussianDate.time(fire))")
        } else if !draft.hasTime {
            Text("Без времени напоминание не отправляется.").ryFont(.subhead).foregroundStyle(RYColor.muted)
        }
    }

    private var pickerSubtitle: String {
        let name = draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Новое дело" : draft.title
        let when = draft.hasTime ? "\(RussianDate.dayMonth(draft.start)), \(RussianDate.time(draft.start))" : RussianDate.dayMonth(draft.start)
        return "\(name) · \(when)\nВыберите одного участника семьи."
    }

    // MARK: Привязки даты и времени

    private var dateBinding: Binding<Date> {
        Binding(get: { draft.start }, set: { new in
            let t = calendar.dateComponents([.hour, .minute], from: draft.start)
            var d = calendar.dateComponents([.year, .month, .day], from: new)
            d.hour = t.hour; d.minute = t.minute
            draft.start = calendar.date(from: d) ?? new
        })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { draft.start }, set: { new in
            let t = calendar.dateComponents([.hour, .minute], from: new)
            var d = calendar.dateComponents([.year, .month, .day], from: draft.start)
            d.hour = t.hour; d.minute = t.minute
            draft.start = calendar.date(from: d) ?? new
        })
    }

    private func applyDefaultTime() {
        draft.start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: draft.start) ?? draft.start
    }

    // MARK: Действия

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch mode {
        case .create(let date):
            draft = TaskDraft(start: date)
            draft.assigneeId = session.userId
            titleFocused = true
        case .editOccurrence(let id), .editSeries(let id):
            guard let occ = occurrence(id) else { return }
            draft = TaskDraft(occurrence: occ, recurrence: series(occ.seriesId)?.recurrence ?? .none)
        }
    }

    private func occurrence(_ id: UUID) -> TaskOccurrenceRecord? {
        (try? context.fetch(FetchDescriptor<TaskOccurrenceRecord>(predicate: #Predicate { $0.id == id })))?.first
    }

    private func series(_ id: UUID) -> TaskSeriesRecord? {
        (try? context.fetch(FetchDescriptor<TaskSeriesRecord>(predicate: #Predicate { $0.id == id })))?.first
    }

    private func submit() {
        submitted = true
        guard draft.problem == nil else { return }
        switch mode {
        case .create: service?.create(draft)
        case .editOccurrence(let id): if let occ = occurrence(id) { service?.update(occ, with: draft) }
        case .editSeries(let id): if let occ = occurrence(id) { service?.updateSeries(from: occ, with: draft) }
        }
        dismiss()
    }

    static func minutesText(_ minutes: Int) -> String {
        switch minutes {
        case 60: "час"
        case 1440: "день"
        default: "\(minutes) \(OverviewView.plural(minutes, "минуту", "минуты", "минут"))"
        }
    }

    static func relativeDay(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "сегодня" }
        if calendar.isDateInTomorrow(date) { return "завтра" }
        if calendar.isDateInYesterday(date) { return "вчера" }
        return RussianDate.dayMonth(date, calendar: calendar)
    }
}
