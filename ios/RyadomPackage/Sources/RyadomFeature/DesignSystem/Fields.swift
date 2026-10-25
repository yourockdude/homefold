import SwiftUI

/// Фон и контур поля ввода из макета.
struct RYFieldBackground: ViewModifier {
    var isError = false
    var isFocused = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.card))
            .overlay(RoundedRectangle(cornerRadius: RYRadius.card)
                .stroke(isError ? RYColor.danger : (isFocused ? RYColor.accent : RYColor.border),
                        lineWidth: isError || isFocused ? 1.5 : 1))
    }
}

extension View {
    func ryField(isError: Bool = false, isFocused: Bool = false) -> some View {
        modifier(RYFieldBackground(isError: isError, isFocused: isFocused))
    }
}

struct RYFieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).ryFont(.caption).foregroundStyle(RYColor.muted) }
}

/// Поле-выбор со шевроном. Содержимое-действие (меню, лист) подставляет вызывающий код.
struct RYSelectLabel: View {
    let value: String
    var systemImage: String = "chevron.down"

    var body: some View {
        HStack {
            Text(value).ryFont(.body).foregroundStyle(RYColor.ink).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: systemImage).font(.system(size: 12)).foregroundStyle(RYColor.muted)
        }
        .ryField()
        .contentShape(Rectangle())
    }
}

/// Поле даты или времени: выглядит как макет, а выбор делает системный `DatePicker`,
/// наложенный поверх почти невидимым — так работают системные доступность и календарь.
struct RYDateField: View {
    let label: String
    let value: String
    @Binding var date: Date
    var components: DatePickerComponents
    var identifier: String

    var body: some View {
        RYSelectLabel(value: value)
            .overlay {
                DatePicker(label, selection: $date, displayedComponents: components)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                    .colorMultiply(.clear)
                    .contentShape(Rectangle())
                    .accessibilityLabel(label)
                    .accessibilityValue(value)
                    .accessibilityIdentifier(identifier)
            }
    }
}
