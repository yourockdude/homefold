import SwiftUI

/// Недельная лента дат: неделя с понедельника, выбранный день — зелёная вертикальная капсула.
struct WeekStrip: View {
    @Binding var selected: Date
    var calendar: Calendar = .current
    @Namespace private var highlight

    private var days: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selected) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                let isToday = calendar.isDateInToday(day)
                Button { withAnimation(RYMotion.snappy) { selected = calendar.startOfDay(for: day) } } label: {
                    VStack(spacing: 6) {
                        Text(RussianDate.shortWeekday(day, calendar: calendar))
                            .ryFont(.micro).foregroundStyle(isSelected ? RYColor.onAccent.opacity(0.85) : RYColor.muted)
                        Text("\(calendar.component(.day, from: day))")
                            .ryFont(isSelected ? RYType.h4M : RYType.h4N)
                            .foregroundStyle(isSelected ? RYColor.onAccent : (isToday ? RYColor.accent : RYColor.ink))
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .background {
                        if isSelected {
                            Capsule().fill(RYColor.accentFill).padding(.horizontal, 2)
                                .matchedGeometryEffect(id: "day-highlight", in: highlight)
                        }
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
            if let moved = calendar.date(byAdding: .day, value: delta, to: selected) { withAnimation(RYMotion.snappy) { selected = moved } }
        })
    }
}
