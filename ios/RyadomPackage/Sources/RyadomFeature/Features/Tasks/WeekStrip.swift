import SwiftUI

/// Недельная лента дат: неделя с понедельника, выбранный день — зелёная вертикальная капсула.
struct WeekStrip: View {
    @Binding var selected: Date
    var calendar: Calendar = .current

    private var days: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selected) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                let isToday = calendar.isDateInToday(day)
                Button { selected = calendar.startOfDay(for: day) } label: {
                    VStack(spacing: 6) {
                        Text(RussianDate.shortWeekday(day, calendar: calendar))
                            .font(.system(size: 11)).foregroundStyle(isSelected ? .white.opacity(0.85) : RYColor.muted)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .white : (isToday ? RYColor.accent : RYColor.ink))
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background {
                        if isSelected { Capsule().fill(RYColor.accent).padding(.horizontal, 2) }
                    }
                    .contentShape(Rectangle())
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
