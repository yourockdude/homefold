import SwiftUI
import SwiftData

/// Настройки профиля: профиль и семья, уведомления, защита документов (Figma 45:3062).
/// Изменения копятся в черновике и применяются кнопкой «Сохранить настройки».
struct SettingsView: View {
    var onOpenFamily: () -> Void = {}
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<MemberRecord> { !$0.isInvited }, sort: \MemberRecord.displayName) private var members: [MemberRecord]
    @Query private var families: [FamilyRecord]

    @State private var draft = NotificationSettings()
    @State private var faceID = false
    @State private var loaded = false
    @State private var saved = false
    @State private var showDiscard = false
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var avatarTarget: MemberRecord?

    private let leadOptions: [(Int, String)] = [
        (0, "В момент срока"), (10, "За 10 минут"), (30, "За 30 минут"), (60, "За час"), (1440, "За день"),
    ]

    private var me: MemberRecord? { members.first { $0.id == session.userId } ?? members.first }
    private var family: FamilyRecord? { families.first }
    private var hasChanges: Bool {
        draft != session.settings.notifications || faceID != session.documentsLock.isProtectionEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Настройки").ryFont(.title).foregroundStyle(RYColor.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 8).padding(.bottom, 14)
                    VStack(alignment: .leading, spacing: 22) {
                        profileGroup
                        notificationsSection
                        protectionSection
                    }
                    .padding(.bottom, RYSpacing.m)
                }
                .padding(.horizontal, RYSpacing.screen)
            }
            .scrollIndicators(.hidden)
        }
        .background(RYColor.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
        .avatarEditing(target: $avatarTarget)
        .confirmationDialog("Выйти без сохранения?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Не сохранять", role: .destructive) { dismiss() }
            Button("Остаться", role: .cancel) {}
        }
        .alert("Ваше имя", isPresented: $showRename) {
            TextField("Имя", text: $nameDraft)
            Button("Сохранить", action: renameMe)
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Так вас видят в семье.")
        }
        .sensoryFeedback(.success, trigger: saved)
    }

    // MARK: Шапка

    private var topBar: some View {
        HStack {
            RYBackButton("Обзор") {
                if hasChanges { showDiscard = true } else { dismiss() }
            }
            .accessibilityIdentifier("settings.back")
            Spacer()
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, 6).frame(minHeight: 44)
    }

    // MARK: Профиль и семья

    private var profileGroup: some View {
        RYListGroup {
            RYListRow(me?.displayName ?? "Профиль", subtitle: roleText(me), leading: {
                if let me {
                    Button { avatarTarget = me } label: {
                        AvatarView(member: me, diameter: 32).overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill").font(.system(size: 7, weight: .bold))
                                .foregroundStyle(RYColor.onAccent)
                                .frame(width: 14, height: 14)
                                .background(RYColor.accentFill, in: Circle())
                                .overlay(Circle().stroke(RYColor.surface, lineWidth: 1.5))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Изменить фото профиля")
                    .accessibilityIdentifier("settings.avatar")
                }
            }, trailing: {
                Button("Изменить") { nameDraft = me?.displayName ?? ""; showRename = true }
                    .ryFont(.callout).foregroundStyle(RYColor.accent)
                    .accessibilityIdentifier("settings.rename")
            })
            RYListDivider(inset: 44)
            RYListRow(familyTitle, subtitle: familySubtitle, leading: {
                Image(systemName: "person.2").font(.system(size: 18, weight: .light)).foregroundStyle(RYColor.accent)
                    .frame(width: 32)
            }, trailing: {
                Button("Открыть") { onOpenFamily() }
                    .ryFont(.callout).foregroundStyle(RYColor.accent)
                    .accessibilityIdentifier("settings.family")
            })
        }
    }

    private var familyTitle: String { family.map { "Семья \($0.name)" } ?? "Семья" }

    private var familySubtitle: String {
        let n = members.count
        let word = OverviewView.plural(n, "участник", "участника", "участников")
        return "\(me?.isAdmin == true ? "Администратор" : "Участник") · \(n) \(word)"
    }

    private func roleText(_ member: MemberRecord?) -> String {
        member?.isAdmin == true ? "Администратор семьи" : "Участник семьи"
    }

    // MARK: Уведомления

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RYSectionHeader("Уведомления")
            RYListGroup {
                toggleRow("Напоминания о делах", leadText, isOn: $draft.taskReminders, id: "settings.taskReminders")
                if draft.taskReminders {
                    RYListDivider()
                    leadPickerRow
                }
                RYListDivider()
                toggleRow("Покупки семьи", "Новые товары и изменения списка", isOn: $draft.shoppingPush, id: "settings.shoppingPush")
                RYListDivider()
                toggleRow("Тихие часы", quietText, isOn: $draft.quietHoursEnabled, id: "settings.quietHours")
                if draft.quietHoursEnabled {
                    RYListDivider()
                    timeRow("С", minutes: $draft.quietStartMinutes, id: "settings.quietStart")
                    RYListDivider()
                    timeRow("До", minutes: $draft.quietEndMinutes, id: "settings.quietEnd")
                }
            }
            .animation(RYMotion.snappy, value: draft.taskReminders)
            .animation(RYMotion.snappy, value: draft.quietHoursEnabled)
        }
    }

    private var leadText: String {
        let label = leadOptions.first { $0.0 == draft.defaultReminderMinutes }?.1 ?? "За \(draft.defaultReminderMinutes) мин"
        return draft.defaultReminderMinutes == 0 ? label : "\(label) до срока"
    }

    private var quietText: String {
        "С \(timeString(draft.quietStartMinutes)) до \(timeString(draft.quietEndMinutes))"
    }

    private var leadPickerRow: some View {
        HStack {
            Text("Напоминать").ryFont(.body).foregroundStyle(RYColor.ink)
            Spacer()
            Picker("Напоминать", selection: $draft.defaultReminderMinutes) {
                ForEach(leadOptions, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden().tint(RYColor.accent)
            .accessibilityIdentifier("settings.leadPicker")
        }
        .frame(minHeight: 50)
    }

    private func timeRow(_ title: String, minutes: Binding<Int>, id: String) -> some View {
        HStack {
            Text(title).ryFont(.body).foregroundStyle(RYColor.ink)
            Spacer()
            DatePicker(title, selection: dateBinding(minutes), displayedComponents: .hourAndMinute)
                .labelsHidden().tint(RYColor.accent)
                .accessibilityIdentifier(id)
        }
        .frame(minHeight: 50)
    }

    private func toggleRow(_ title: String, _ subtitle: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).ryFont(.body).foregroundStyle(RYColor.ink)
                Text(subtitle).ryFont(.subhead).foregroundStyle(RYColor.muted)
            }
        }
        .tint(RYColor.accentFill)
        .padding(.vertical, 12).frame(minHeight: 62)
        .accessibilityIdentifier(id)
    }

    // MARK: Защита документов

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RYSectionHeader("Защита документов")
            RYListGroup {
                toggleRow("Face ID для документов", "Проверка при каждом открытии", isOn: $faceID, id: "settings.faceID")
            }
        }
    }

    // MARK: Сохранение

    private var saveBar: some View {
        Button(action: save) { Text("Сохранить настройки") }
            .buttonStyle(.ryPrimary)
            .disabled(!hasChanges)
            .accessibilityIdentifier("settings.save")
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, 8)
            .background(RYColor.background)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        draft = session.settings.notifications
        faceID = session.documentsLock.isProtectionEnabled
    }

    private func save() {
        session.settings.notifications = draft
        session.documentsLock.isProtectionEnabled = faceID
        saved.toggle()
        let service = session.taskService(context: context)
        Task { await service?.reconcileReminders() }
        dismiss()
    }

    private func renameMe() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let me, !name.isEmpty, name != me.displayName else { return }
        me.displayName = name
        try? context.save()
    }

    // MARK: Время

    private func dateBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }

    private func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
