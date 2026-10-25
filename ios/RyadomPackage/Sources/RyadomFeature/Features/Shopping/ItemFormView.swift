import SwiftUI
import SwiftData

/// Лист создания и редактирования товара: «Отмена · заголовок · Добавить/Готово».
struct ItemFormView: View {
    enum Mode {
        case add(ShoppingListRecord)
        case edit(ShoppingItemRecord)
    }

    let mode: Mode
    let service: ShoppingService?
    let members: [MemberRecord]
    var onDeleted: (ShoppingItemRecord) -> Void = { _ in }

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ShoppingItemDraft()
    @State private var quantityText = "1"
    @State private var submitted = false
    @State private var confirmDelete = false
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var isEdit: Bool { if case .edit = mode { true } else { false } }
    private var unit: ShoppingUnit { ShoppingUnit(rawValue: draft.unit) ?? .piece }

    private var nameError: String? {
        submitted && draft.problem == .emptyName ? "Введите название, чтобы добавить покупку." : nil
    }
    private var quantityError: String? {
        submitted && draft.problem == .invalidQuantity ? "Количество должно быть больше нуля." : nil
    }

    var body: some View {
        RYSheetScaffold(title: isEdit ? "Изменить покупку" : "Новая покупка",
                        confirmTitle: isEdit ? "Готово" : "Добавить",
                        confirmIdentifier: "item.submit",
                        onCancel: { dismiss() }, onConfirm: submit) {
            Text("В общий список · видно всей семье").ryFont(.subhead).foregroundStyle(RYColor.muted)
            VStack(alignment: .leading, spacing: 16) {
                nameField
                quantityAndCategory
                assigneeField
                noteField
            }
            if submitted, draft.problem != nil {
                Text("Остальные поля сохранены. Заполните название и попробуйте ещё раз.")
                    .ryFont(.subhead).foregroundStyle(RYColor.muted)
            } else if let notice {
                RYNotice(systemImage: notice.icon, title: notice.title, text: notice.text)
            }
            if isEdit {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text("Удалить товар").ryFont(.body).foregroundStyle(RYColor.danger)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .accessibilityIdentifier("item.delete")
            }
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

    // MARK: Поля

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Что купить" + (nameError != nil ? " · обязательно" : ""))
                .ryFont(.subhead).foregroundStyle(nameError != nil ? RYColor.danger : RYColor.muted)
            TextField("Название товара", text: $draft.name)
                .focused($nameFocused)
                .ryFont(.body).foregroundStyle(RYColor.ink)
                .submitLabel(.done)
                .ryField(isError: nameError != nil, isFocused: nameFocused)
                .accessibilityIdentifier("item.name")
            if let nameError { Text(nameError).ryFont(.subhead).foregroundStyle(RYColor.danger) }
        }
    }

    private var quantityAndCategory: some View {
        VStack(alignment: .leading, spacing: 6) {
            RYListGroup {
                HStack(spacing: 2) {
                    Text("Количество").ryFont(.body).foregroundStyle(RYColor.ink)
                    Spacer(minLength: 4)
                    TextField("1", text: $quantityText)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .ryFont(.body).foregroundStyle(quantityError == nil ? RYColor.ink : RYColor.danger)
                        .frame(width: 44)
                        .onChange(of: quantityText) { _, new in draft.quantity = ShoppingFormat.parseQuantity(new) ?? 0 }
                        .accessibilityLabel("Количество")
                        .accessibilityIdentifier("item.quantity")
                    Menu {
                        Picker("Единица", selection: $draft.unit) {
                            ForEach(ShoppingUnit.allCases.map(\.rawValue), id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Text(draft.unit).ryFont(.body).foregroundStyle(RYColor.ink)
                            .frame(minWidth: 28, minHeight: 44)
                    }
                    .accessibilityLabel("Единица измерения")
                    .accessibilityIdentifier("item.unit")
                    .padding(.trailing, 4)
                    QuantityStepper(onMinus: { adjust(-unit.step) }, onPlus: { adjust(unit.step) })
                }
                .frame(minHeight: 54)
                RYListDivider()
                Menu {
                    Picker("Категория", selection: $draft.category) {
                        ForEach(ShoppingCategory.allCases.map(\.rawValue), id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    RYListRow("Категория", subtitle: draft.category, leading: { EmptyView() }, trailing: {
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .medium)).foregroundStyle(RYColor.accent)
                    })
                }
                .accessibilityIdentifier("item.category")
            }
            if let quantityError { Text(quantityError).ryFont(.subhead).foregroundStyle(RYColor.danger) }
        }
    }

    private var assigneeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Кто купит").ryFont(.subhead).foregroundStyle(RYColor.muted)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(title: "Любой", member: nil, selected: draft.assigneeId == nil) { draft.assigneeId = nil }
                    ForEach(members) { m in
                        chip(title: m.displayName, member: m, selected: draft.assigneeId == m.id) { draft.assigneeId = m.id }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(title: String, member: MemberRecord?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let member {
                    AvatarView(name: member.displayName, tone: member.tone, diameter: 24)
                } else {
                    Image(systemName: "person.2").font(.system(size: 12, weight: .light)).foregroundStyle(RYColor.accent)
                        .frame(width: 24, height: 24).background(RYColor.accentTint, in: Circle())
                }
                Text(title).ryFont(.subhead).fontWeight(.medium).foregroundStyle(RYColor.ink)
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(RYColor.accent) }
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(selected ? RYColor.accentTint : RYColor.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? RYColor.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Заметка · необязательно").ryFont(.subhead).foregroundStyle(RYColor.muted)
            TextField("Например, для салата", text: $draft.note)
                .ryFont(.body).foregroundStyle(RYColor.ink)
                .ryField()
                .accessibilityIdentifier("item.note")
        }
    }

    /// Плашка под формой: кого уведомим при добавлении или что произойдёт при правке.
    private var notice: (icon: String, title: String, text: String)? {
        if isEdit {
            return ("person.2", "Список обновится у всех", "Изменения сохранятся в этой покупке. Новый товар не будет добавлен.")
        }
        guard let id = draft.assigneeId, id != session.userId,
              let m = members.first(where: { $0.id == id }) else { return nil }
        return ("bell", "\(m.displayName) получит уведомление", "Когда вы добавите покупку в общий список.")
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
}

/// Шаговый переключатель «− | +» из макета: 100×34, r9, фон #F2F2F7.
struct QuantityStepper: View {
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMinus) { Image(systemName: "minus").font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, maxHeight: .infinity) }
                .accessibilityLabel("Уменьшить количество").accessibilityIdentifier("item.minus")
            Rectangle().fill(RYColor.divider).frame(width: 1, height: 20)
            Button(action: onPlus) { Image(systemName: "plus").font(.system(size: 15, weight: .medium)).frame(maxWidth: .infinity, maxHeight: .infinity) }
                .accessibilityLabel("Увеличить количество").accessibilityIdentifier("item.plus")
        }
        .foregroundStyle(RYColor.accent)
        .frame(width: 100, height: 34)
        .background(RYColor.background, in: RoundedRectangle(cornerRadius: 9))
    }
}
