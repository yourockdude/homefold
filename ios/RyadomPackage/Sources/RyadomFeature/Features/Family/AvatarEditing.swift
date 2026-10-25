import SwiftUI
import PhotosUI

/// Смена фото профиля: «Выбрать фото» из галереи и «Удалить фото». Окно открывается, когда `target` не nil.
private struct AvatarEditingModifier: ViewModifier {
    @Binding var target: MemberRecord?
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context

    @State private var showActions = false
    @State private var showPicker = false
    @State private var editing: MemberRecord?
    @State private var item: PhotosPickerItem?
    @State private var errorText: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: target) { _, new in if new != nil { showActions = true } }
            .onChange(of: showActions) { _, shown in if !shown { target = nil } }
            .confirmationDialog(target.map { "Фото: \($0.displayName)" } ?? "Фото", isPresented: $showActions, titleVisibility: .visible) {
                Button("Выбрать фото") { editing = target; showPicker = true }
                if target?.avatarData != nil {
                    Button("Удалить фото", role: .destructive) { apply(nil, to: target) }
                }
                Button("Отмена", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPicker, selection: $item, matching: .images)
            .task(id: item) {
                guard let item, let member = editing else { return }
                defer { self.item = nil }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    errorText = FamilyError.invalidImage.localizedDescription
                    return
                }
                apply(data, to: member)
            }
            .alert("Фото не загружено", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("Понятно", role: .cancel) {}
            } message: { Text(errorText ?? "") }
    }

    private func apply(_ photo: Data?, to member: MemberRecord?) {
        guard let member else { return }
        do { try FamilyService(context: context).setAvatar(photo, for: member, by: session.userId) }
        catch { errorText = error.localizedDescription }
    }
}

extension View {
    func avatarEditing(target: Binding<MemberRecord?>) -> some View {
        modifier(AvatarEditingModifier(target: target))
    }
}
