import SwiftUI

/// Недельная лента дат: неделя с понедельника, выбранный день — тёмно-зелёная пилюля.
struct WeekStrip: View {
    @Binding var selected: Date
    var calendar: Calendar = .current

    private var days: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selected) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                Button { selected = calendar.startOfDay(for: day) } label: {
                    VStack(spacing: 7) {
                        Text(RussianDate.shortWeekday(day, calendar: calendar))
                            .font(.system(size: 9)).foregroundStyle(isSelected ? Color(hex: 0xDCE8D9) : RYColor.muted)
                        Text("\(calendar.component(.day, from: day))")
                            .ryFont(.section).fontWeight(.medium).foregroundStyle(isSelected ? .white : RYColor.ink)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(isSelected ? RYColor.accent : RYColor.background, in: RoundedRectangle(cornerRadius: RYRadius.card))
                    .overlay(RoundedRectangle(cornerRadius: RYRadius.card)
                        .stroke(calendar.isDateInToday(day) && !isSelected ? RYColor.accent.opacity(0.4) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(RussianDate.weekdayDayMonth(day, calendar: calendar))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("day.\(calendar.component(.day, from: day))")
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            let delta = value.translation.width < 0 ? 7 : -7
            if let moved = calendar.date(byAdding: .day, value: delta, to: selected) { selected = moved }
        })
    }
}
