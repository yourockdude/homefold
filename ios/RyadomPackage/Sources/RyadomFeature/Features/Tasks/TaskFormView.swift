import SwiftUI
import SwiftData

/// Создание дела, правка одного выполнения и явная правка серии.
struct TaskFormView: View {
    enum Mode: Hashable {
        case create(Date)
        case editOccurrence(UUID)
        case editSeries(UUID)
    }

    let mode: Mode
    let members: [MemberRecord]
    let familyName: String
    @Binding var path: [TaskRoute]

    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

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
    private var screenTitle: String {
        switch mode {
        case .create: "Новое дело"
        case .editOccurrence: "Изменить дело"
        case .editSeries: "Изменить серию"
        }
    }
    private var titleError: String? { submitted && draft.problem == .emptyTitle ? "Введите название дела." : nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.s) {
                    Text("Для семьи \(RussianNames.familyGenitive(familyName))").ryFont(.caption).foregroundStyle(RYColor.muted)
                    if isSeriesEdit { seriesNotice }
                    titleField
                    assigneeField
                    dateTimeRow
                    if !isEditOccurrence { recurrenceField }
                    placeField
                    noteField
                    if isCreate { checklistField }
                    reminderField
                    tagField
                    reminderFootnote
                }
                .padding(.horizontal, RYSpacing.screen)
                .padding(.bottom, RYSpacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(RYColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: submit) {
                Label(isCreate ? "Создать дело" : "Сохранить", systemImage: isCreate ? "plus" : "checkmark")
            }
            .buttonStyle(.ryPrimary)
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
            .background(RYColor.background)
            .accessibilityIdentifier("task.submit")
        }
        .sheet(isPresented: $showAssigneeSheet) {
            MemberPickerSheet(title: "Кто возьмёт дело?", subtitle: "Выберите одного участника семьи.",
                              members: members, currentUserId: session.userId, selection: $assigneeSelection) {
                draft.assigneeId = assigneeSelection
            }
        }
        .onAppear(perform: load)
    }

    private var isEditOccurrence: Bool { if case .editOccurrence = mode { true } else { false } }

    // MARK: Части формы

    private var topBar: some View {
        HStack(spacing: RYSpacing.s) {
            Button(action: close) { Image(systemName: "arrow.left").font(.system(size: 18)).foregroundStyle(RYColor.ink) }
                .accessibilityLabel("Назад")
            Text(screenTitle).ryFont(.section).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(RYColor.ink)
                    .frame(width: 40, height: 40).background(RYColor.surface, in: Circle())
            }
            .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.m)
    }

    private var seriesNotice: some View {
        RYStatusBanner(kind: .info, text: "Изменения применятся к этому и следующим делам серии. Выполненные и отдельно изменённые дела останутся как были.")
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Что нужно сделать" + (titleError != nil ? " *" : ""))
            TextField("Например, полить растения", text: $draft.title)
                .focused($titleFocused).ryFont(.body).foregroundStyle(RYColor.ink)
                .ryField(isError: titleError != nil, isFocused: titleFocused)
                .accessibilityIdentifier("task.title")
            if let titleError { Text(titleError).ryFont(.caption).foregroundStyle(RYColor.danger) }
        }
    }

    private var assigneeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Ответственный")
            Button {
                assigneeSelection = draft.assigneeId
                showAssigneeSheet = true
            } label: {
                RYSelectLabel(value: members.first { $0.id == draft.assigneeId }?.displayName ?? "Выберите участника")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task.assignee")
        }
    }

    private var dateTimeRow: some View {
        HStack(alignment: .top, spacing: RYSpacing.s) {
            VStack(alignment: .leading, spacing: 6) {
                RYFieldLabel("Дата")
                RYDateField(label: "Дата", value: RussianDate.dayMonth(draft.start), date: dateBinding,
                            components: .date, identifier: "task.date")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    RYFieldLabel("Время")
                    Spacer()
                    Button(draft.hasTime ? "Убрать" : "Указать") {
                        draft.hasTime.toggle()
                        if draft.hasTime { applyDefaultTime() }
                    }
                    .ryFont(.caption).foregroundStyle(RYColor.accent)
                    .accessibilityIdentifier("task.timeToggle")
                }
                if draft.hasTime {
                    RYDateField(label: "Время", value: RussianDate.time(draft.start), date: timeBinding,
                                components: .hourAndMinute, identifier: "task.time")
                } else {
                    RYSelectLabel(value: "Без времени", systemImage: "sun.max")
                }
            }
        }
    }

    private var recurrenceField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Повторять")
            Menu {
                Picker("Повторять", selection: $draft.recurrence) {
                    ForEach(Recurrence.allCases, id: \.self) { Text($0.title(for: draft.start)).tag($0) }
                }
            } label: { RYSelectLabel(value: draft.recurrence.title(for: draft.start)) }
                .accessibilityIdentifier("task.recurrence")
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
        VStack(alignment: .leading, spacing: 8) {
            RYFieldLabel("Чек-лист · необязательно")
            ForEach(draft.checklist.indices, id: \.self) { index in
                HStack {
                    TextField("Пункт", text: $draft.checklist[index]).ryFont(.body).foregroundStyle(RYColor.ink)
                        .accessibilityIdentifier("task.check.\(index)")
                    Button { draft.checklist.remove(at: index) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(RYColor.muted)
                    }
                    .accessibilityLabel("Удалить пункт")
                }
                .ryField()
            }
            Button { draft.checklist.append("") } label: {
                Label("Добавить пункт", systemImage: "plus").ryFont(.body).foregroundStyle(RYColor.accent)
                    .frame(minHeight: 40)
            }
            .accessibilityIdentifier("task.addCheck")
        }
    }

    private var reminderField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Напоминание")
            Menu {
                Picker("Напоминание", selection: $draft.reminderMinutes) {
                    ForEach(reminderOptions, id: \.1) { Text($0.1).tag($0.0) }
                }
            } label: {
                RYSelectLabel(value: reminderOptions.first { $0.0 == draft.reminderMinutes }?.1 ?? "Без напоминания")
            }
            .disabled(!draft.hasTime)
            .opacity(draft.hasTime ? 1 : 0.5)
            .accessibilityIdentifier("task.reminder")
        }
    }

    private var tagField: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYFieldLabel("Метка · необязательно")
            Menu {
                Picker("Метка", selection: $draft.tag) {
                    ForEach(tagOptions, id: \.self) { Text($0.isEmpty ? "Без метки" : $0).tag($0) }
                }
            } label: { RYSelectLabel(value: draft.tag.isEmpty ? "Без метки" : draft.tag) }
                .accessibilityIdentifier("task.tag")
        }
    }

    @ViewBuilder private var reminderFootnote: some View {
        if draft.hasTime, let minutes = draft.reminderMinutes {
            let fire = draft.start.addingTimeInterval(-TimeInterval(minutes) * 60)
            let who = members.first { $0.id == draft.assigneeId }.map { RussianNames.dative($0.displayName) } ?? "всем"
            let lead = minutes == 0 ? "Напомнить в момент срока" : "Напомнить за \(Self.minutesText(minutes))"
            Text("\(lead) · \(who) \(Self.relativeDay(fire, calendar: calendar)) в \(RussianDate.time(fire))")
                .ryFont(.caption).foregroundStyle(RYColor.muted)
        } else if !draft.hasTime {
            Text("Без времени напоминание не отправляется.").ryFont(.caption).foregroundStyle(RYColor.muted)
        }
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
        close()
    }

    private func close() { if !path.isEmpty { path.removeLast() } }

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
