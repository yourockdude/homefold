import SwiftUI
import SwiftData

/// «Моя семья»: название, участники, приглашение и удаление (удаляет и приглашает администратор).
struct FamilyView: View {
    var backTitle = "Обзор"
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MemberRecord.toneIndex) private var allMembers: [MemberRecord]
    @Query private var families: [FamilyRecord]

    @State private var showAdd = false
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var pendingRemoval: MemberRecord?
    @State private var showRemoval = false
    @State private var errorText: String?

    /// Сначала участники, затем приглашённые.
    private var members: [MemberRecord] { allMembers.filter { !$0.isInvited } + allMembers.filter(\.isInvited) }
    private var family: FamilyRecord? { families.first }
    private var me: MemberRecord? { members.first { $0.id == session.userId } }
    private var isAdmin: Bool { me?.isAdmin == true }
    private var limit: Int { FamilyService.memberLimit(isPremium: family?.isPremium ?? false) }
    private var service: FamilyService { FamilyService(context: context) }
    private var awaitingLink: Bool { members.contains { $0.isInvited && $0.inviteURL == nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RYBackButton(backTitle) { dismiss() }.accessibilityIdentifier("family.back")
                Spacer()
            }
            .padding(.horizontal, RYSpacing.screen).padding(.top, 6).frame(minHeight: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Моя семья").ryFont(.title).foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
                        Text("\(members.count) из \(limit) участников").ryFont(.callout).foregroundStyle(RYColor.muted)
                            .accessibilityIdentifier("family.count")
                    }
                    .padding(.top, 8)
                    nameGroup
                    RYSectionHeader("Участники")
                    membersGroup
                    if let errorText {
                        RYNotice(systemImage: "exclamationmark.triangle", text: errorText, tint: RYColor.danger.opacity(0.12), ink: RYColor.danger)
                    }
                    if awaitingLink {
                        RYNotice(systemImage: "paperplane", title: "Приглашения ждут отправки",
                                 text: "Ссылка для приглашённых появится, когда приложение свяжется с сервером.")
                    }
                }
                .padding(.horizontal, RYSpacing.screen).padding(.bottom, RYSpacing.m)
            }
            .scrollIndicators(.hidden)
        }
        .background(RYColor.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { addBar }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Название семьи", isPresented: $showRename) {
            TextField("Название", text: $nameDraft)
            Button("Сохранить", action: rename)
            Button("Отмена", role: .cancel) {}
        }
        .sheet(isPresented: $showAdd) { AddMemberSheet(limit: limit) }
        .ryConfirm(isPresented: $showRemoval, systemImage: "person.badge.minus",
                   title: pendingRemoval?.isInvited == true ? "Отозвать приглашение?" : "Убрать из семьи?",
                   message: removalMessage, confirmTitle: pendingRemoval?.isInvited == true ? "Отозвать" : "Убрать",
                   onConfirm: confirmRemoval)
        .sensoryFeedback(.warning, trigger: errorText)
    }

    // MARK: Блоки

    private var nameGroup: some View {
        RYListGroup {
            RYListRow(family.map { "Семья \($0.name)" } ?? "Семья", subtitle: "Название видят все участники", leading: {
                Image(systemName: "house").font(.system(size: 18, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 32)
            }, trailing: {
                if isAdmin {
                    Button("Изменить") { nameDraft = family?.name ?? ""; showRename = true }
                        .ryFont(.callout).foregroundStyle(RYColor.accent).accessibilityIdentifier("family.rename")
                }
            })
        }
    }

    private var membersGroup: some View {
        RYListGroup {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if index > 0 { RYListDivider(inset: 44) }
                memberRow(member)
            }
        }
    }

    private func memberRow(_ member: MemberRecord) -> some View {
        let isMe = member.id == session.userId
        return RYListRow(isMe ? "\(member.displayName) (вы)" : member.displayName, subtitle: subtitle(member), leading: {
            AvatarView(name: member.displayName, tone: member.tone, diameter: 32).opacity(member.isInvited ? 0.55 : 1)
        }, trailing: {
            HStack(spacing: 14) {
                if let url = member.inviteURL.flatMap(URL.init(string:)) {
                    ShareLink(item: url, message: Text("Присоединяйтесь к семье в HomeFold")) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .regular))
                            .foregroundStyle(RYColor.accent)
                    }
                    .accessibilityLabel("Отправить приглашение: \(member.displayName)")
                }
                if isAdmin && !isMe {
                    Button { pendingRemoval = member; showRemoval = true } label: {
                        Image(systemName: "person.badge.minus").font(.system(size: 17, weight: .regular))
                            .foregroundStyle(RYColor.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(member.isInvited ? "Отозвать приглашение: \(member.displayName)" : "Убрать из семьи: \(member.displayName)")
                    .accessibilityIdentifier("family.remove.\(member.displayName)")
                }
            }
        })
        .accessibilityElement(children: .contain)
    }

    private func subtitle(_ member: MemberRecord) -> String {
        if member.isInvited { return "Приглашён · ждёт подтверждения" }
        return member.isAdmin ? "Администратор" : "Участник"
    }

    @ViewBuilder private var addBar: some View {
        if isAdmin {
            Button { showAdd = true } label: { Text("Добавить участника") }
                .buttonStyle(.ryPrimary)
                .accessibilityIdentifier("family.add")
                .padding(.horizontal, RYSpacing.screen).padding(.vertical, 8)
                .background(RYColor.background)
        }
    }

    private var removalMessage: String {
        guard let member = pendingRemoval else { return "" }
        return member.isInvited
            ? "\(member.displayName) не сможет присоединиться по этому приглашению."
            : "\(member.displayName) потеряет доступ к спискам, делам и документам семьи."
    }

    // MARK: Действия

    private func rename() {
        guard let family else { return }
        perform { try service.rename(family, to: nameDraft, by: session.userId) }
    }

    private func confirmRemoval() {
        guard let member = pendingRemoval else { return }
        pendingRemoval = nil
        perform { try service.remove(member, by: session.userId) }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); errorText = nil } catch { errorText = error.localizedDescription }
    }
}

/// Приглашение нового участника по имени.
private struct AddMemberSheet: View {
    let limit: Int
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var families: [FamilyRecord]

    @State private var name = ""
    @State private var submitted = false
    @State private var errorText: String?
    @FocusState private var focused: Bool

    var body: some View {
        RYSheetScaffold(title: "Новый участник", confirmTitle: "Добавить", confirmIdentifier: "family.add.confirm",
                        onCancel: { dismiss() }, onConfirm: submit) {
            Text("Кого пригласить в семью").ryFont(.subhead).foregroundStyle(RYColor.muted)
            RYTextField("Имя", text: $name, placeholder: "Например, Михаил",
                        error: errorText ?? (submitted && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Введите имя" : nil))
                .focused($focused)
                .accessibilityIdentifier("family.add.name")
            RYNotice(systemImage: "link", title: "Приглашение по ссылке",
                     text: "Участник получит ссылку, откроет её на своём телефоне и войдёт в семью. Приглашение действует 7 дней.")
            Text("В семье до \(limit) участников.").ryFont(.caption).foregroundStyle(RYColor.muted)
        }
        .onAppear { focused = true }
    }

    private func submit() {
        submitted = true
        guard let family = families.first else { return }
        do {
            try FamilyService(context: context).invite(name: name, to: family, by: session.userId)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
