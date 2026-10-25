import SwiftUI
import SwiftData

/// Создание и редактирование товара.
struct ItemFormView: View {
    enum Mode {
        case add(ShoppingListRecord)
        case edit(ShoppingItemRecord)
    }

    let mode: Mode
    let service: ShoppingService?
    let members: [MemberRecord]
    @Binding var path: [ShoppingRoute]
    var onDeleted: (ShoppingItemRecord) -> Void = { _ in }

    @Environment(AppSession.self) private var session
    @State private var draft = ShoppingItemDraft()
    @State private var quantityText = "1"
    @State private var submitted = false
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    private var isEdit: Bool { if case .edit = mode { true } else { false } }
    private var unit: ShoppingUnit { ShoppingUnit(rawValue: draft.unit) ?? .piece }

    private var nameError: String? {
        submitted && draft.problem == .emptyName ? "Введите название, чтобы добавить покупку." : nil
    }
    private var quantityError: String? {
        submitted && draft.problem == .invalidQuantity ? "Количество должно быть больше нуля." : nil
    }
    private var assigneeNote: String? {
        guard let id = draft.assigneeId, id != session.userId,
              let m = members.first(where: { $0.id == id }) else { return nil }
        return "\(m.displayName) получит уведомление, когда вы добавите покупку."
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: RYSpacing.s) {
                    Label("В общий список · видно всей семье", systemImage: "person.2")
                        .ryFont(.caption).foregroundStyle(RYColor.muted)
                    nameField
                    quantityRow
                    categoryField
                    assigneeField
                    noteField
                    if submitted, draft.problem != nil {
                        Text("Остальные поля сохранены. Заполните название и попробуйте ещё раз.")
                            .ryFont(.caption).foregroundStyle(RYColor.muted)
                    } else if let assigneeNote {
                        Label(assigneeNote, systemImage: "bell").ryFont(.caption).foregroundStyle(RYColor.muted)
                    }
                    if isEdit {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Удалить товар", systemImage: "trash").ryFont(.body).foregroundStyle(RYColor.danger)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityIdentifier("item.delete")
                    }
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
                Label(isEdit ? "Сохранить" : "Добавить в список", systemImage: isEdit ? "checkmark" : "plus")
            }
            .buttonStyle(.ryPrimary)
            .padding(.horizontal, RYSpacing.screen).padding(.vertical, RYSpacing.s)
            .background(RYColor.background)
            .accessibilityIdentifier("item.submit")
        }
        .ryConfirm(isPresented: $confirmDelete, title: "Удалить товар?",
                   message: "Товар исчезнет из общего списка у всех участников. Сразу после удаления его можно вернуть.",
                   confirmTitle: "Удалить") {
            if case .edit(let item) = mode {
                service?.delete(item)
                onDeleted(item)
                dismiss()
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Части формы

    private var topBar: some View {
        HStack(spacing: RYSpacing.s) {
            Button(action: dismiss) {
                Image(systemName: "arrow.left").font(.system(size: 18, weight: .regular)).foregroundStyle(RYColor.ink)
            }
            .accessibilityLabel("Назад")
            Text(isEdit ? "Редактировать покупку" : "Новая покупка").ryFont(.section)
                .foregroundStyle(RYColor.ink).accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(RYColor.ink)
                    .frame(width: 40, height: 40).background(RYColor.surface, in: Circle())
            }
            .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, RYSpacing.screen).padding(.top, RYSpacing.s).padding(.bottom, RYSpacing.m)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Что купить" + (nameError != nil ? " *" : "")).ryFont(.caption).foregroundStyle(RYColor.muted)
            TextField("Название товара", text: $draft.name)
                .focused($nameFocused)
                .ryFont(.body).foregroundStyle(RYColor.ink)
                .submitLabel(.done)
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
                .overlay(RoundedRectangle(cornerRadius: RYRadius.card)
                    .stroke(nameError != nil ? RYColor.danger : (nameFocused ? RYColor.accent : RYColor.border),
                            lineWidth: nameError != nil || nameFocused ? 1.5 : 1))
                .accessibilityIdentifier("item.name")
            if let nameError { Text(nameError).ryFont(.caption).foregroundStyle(RYColor.danger) }
        }
    }

    private var quantityRow: some View {
        HStack(alignment: .top, spacing: RYSpacing.s) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Количество").ryFont(.caption).foregroundStyle(RYColor.muted)
                HStack {
                    Button { adjust(-unit.step) } label: { Image(systemName: "minus").frame(width: 40, height: 52) }
                        .accessibilityLabel("Уменьшить количество")
                    TextField("1", text: $quantityText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.center)
                        .ryFont(.bodyMedium).foregroundStyle(RYColor.ink)
                        .onChange(of: quantityText) { _, new in draft.quantity = ShoppingFormat.parseQuantity(new) ?? 0 }
                        .accessibilityLabel("Количество")
                    Button { adjust(unit.step) } label: { Image(systemName: "plus").frame(width: 40, height: 52) }
                        .accessibilityLabel("Увеличить количество")
                }
                .foregroundStyle(RYColor.accent)
                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
                .overlay(RoundedRectangle(cornerRadius: RYRadius.card)
                    .stroke(quantityError != nil ? RYColor.danger : RYColor.border, lineWidth: 1))
                if let quantityError { Text(quantityError).ryFont(.caption).foregroundStyle(RYColor.danger) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Единица").ryFont(.caption).foregroundStyle(RYColor.muted)
                menuField(selection: $draft.unit, options: ShoppingUnit.allCases.map(\.rawValue), id: "item.unit")
                    .frame(maxWidth: 135)
            }
        }
    }

    private var categoryField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Категория").ryFont(.caption).foregroundStyle(RYColor.muted)
            menuField(selection: $draft.category, options: ShoppingCategory.allCases.map(\.rawValue), id: "item.category")
        }
    }

    private func menuField(selection: Binding<String>, options: [String], id: String) -> some View {
        Menu {
            Picker("", selection: selection) { ForEach(options, id: \.self) { Text($0).tag($0) } }
        } label: {
            HStack {
                Text(selection.wrappedValue).ryFont(.body).foregroundStyle(RYColor.ink)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(RYColor.muted)
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            .overlay(RoundedRectangle(cornerRadius: RYRadius.card).stroke(RYColor.border, lineWidth: 1))
        }
        .accessibilityIdentifier(id)
    }

    private var assigneeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Кто купит").ryFont(.caption).foregroundStyle(RYColor.muted)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(title: "Любой", tone: nil, selected: draft.assigneeId == nil) { draft.assigneeId = nil }
                    ForEach(members) { m in
                        chip(title: m.displayName, tone: m, selected: draft.assigneeId == m.id) { draft.assigneeId = m.id }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(title: String, tone: MemberRecord?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let tone { AvatarView(name: tone.displayName, tone: tone.tone, diameter: 22) }
                Text(title).ryFont(.body).foregroundStyle(RYColor.ink)
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(RYColor.accent) }
            }
            .padding(.horizontal, 10).frame(minHeight: 40)
            .background(selected ? RYColor.accentTint : RYColor.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? RYColor.accent : RYColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Заметка · необязательно").ryFont(.caption).foregroundStyle(RYColor.muted)
            TextField("Например, для салата", text: $draft.note)
                .ryFont(.body).foregroundStyle(RYColor.ink)
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
                .overlay(RoundedRectangle(cornerRadius: RYRadius.card).stroke(RYColor.border, lineWidth: 1))
                .accessibilityIdentifier("item.note")
        }
    }

    // MARK: Действия

    private func load() {
        guard !loaded else { return }
        loaded = true
        if case .edit(let item) = mode {
            draft = ShoppingItemDraft(item)
            quantityText = ShoppingFormat.quantity(item.quantity)
        } else {
            nameFocused = true
        }
    }
    @State private var loaded = false

    private func adjust(_ delta: Double) {
        let next = max(unit.step, (draft.quantity > 0 ? draft.quantity : 0) + delta)
        draft.quantity = next
        quantityText = ShoppingFormat.quantity(next)
    }

    private func submit() {
        submitted = true
        guard draft.problem == nil else { return }
        switch mode {
        case .add(let list): service?.add(draft, to: list)
        case .edit(let item): service?.update(item, with: draft)
        }
        dismiss()
    }

    private func dismiss() { if !path.isEmpty { path.removeLast() } }
}
