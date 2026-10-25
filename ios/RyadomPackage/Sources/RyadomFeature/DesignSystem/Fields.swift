import SwiftUI

/// Белое поле ввода r14 без контура; при ошибке — красная обводка, при фокусе — акцентная.
struct RYFieldBackground: ViewModifier {
    var isError = false
    var isFocused = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(RYColor.surface, in: RoundedRectangle(cornerRadius: RYRadius.field))
            .overlay(RoundedRectangle(cornerRadius: RYRadius.field)
                .stroke(isError ? RYColor.danger : (isFocused ? RYColor.accent : .clear), lineWidth: 1.5))
    }
}

extension View {
    func ryField(isError: Bool = false, isFocused: Bool = false) -> some View {
        modifier(RYFieldBackground(isError: isError, isFocused: isFocused))
    }
}

/// Подпись над полем: 13 muted.
struct RYFieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).ryFont(.subhead).foregroundStyle(RYColor.muted) }
}

/// Поле-выбор со шевроном (отдельное поле на белом фоне).
struct RYSelectLabel: View {
    let value: String
    var systemImage: String = "chevron.up.chevron.down"

    var body: some View {
        HStack {
            Text(value).ryFont(.body).foregroundStyle(RYColor.ink).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: systemImage).font(.system(size: 12, weight: .medium)).foregroundStyle(RYColor.accent)
        }
        .ryField()
        .contentShape(Rectangle())
    }
}

/// Строка группы «подпись слева — значение справа акцентным цветом». Значение — произвольный контент
/// (меню, дата, переключатель).
struct RYValueRow<Value: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 18, weight: .light)).foregroundStyle(RYColor.accent).frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ryFont(.body).foregroundStyle(RYColor.ink)
                if let subtitle { Text(subtitle).ryFont(.subhead).foregroundStyle(RYColor.muted) }
            }
            Spacer(minLength: 8)
            value.ryFont(.body).foregroundStyle(RYColor.accent)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

/// Поле даты или времени: выглядит как значение строки, а выбор делает системный `DatePicker`,
/// наложенный поверх прозрачным — так работают системные доступность и календарь.
struct RYDateField: View {
    let label: String
    let value: String
    @Binding var date: Date
    var components: DatePickerComponents
    var identifier: String
    /// true — отрисовать как значение строки группы (акцентный текст), false — как отдельное белое поле.
    var inline = false

    var body: some View {
        Group {
            if inline {
                Text(value).ryFont(.body).foregroundStyle(RYColor.accent)
            } else {
                RYSelectLabel(value: value, systemImage: "chevron.down")
            }
        }
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
