#if os(iOS)
    import Design
    import EvenCore
    import SwiftUI

    /// Read-only month grid over the loaded calendar window.
    ///
    /// Owner-tinted dots mark the days that carry something; tapping a day
    /// filters the agenda underneath (tapping it again clears the filter). It
    /// never edits — the shared calendar is written by approving drafts and by
    /// the two-way Google sync, not here.
    struct InboxMonthGrid: View {
        /// `YYYY-MM-DD` first day of the loaded window.
        let monthStart: String
        let items: [CalendarItem]
        let selectedDay: String?
        let me: Member?
        let partner: Member?
        let onSelectDay: (String?) -> Void

        private static let columns = Array(
            repeating: GridItem(.flexible(), spacing: 2),
            count: 7
        )

        /// Monday-first — the household week the beam settles on.
        private static var gridCalendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = 2
            return calendar
        }

        var body: some View {
            VStack(spacing: 8) {
                weekdayHeader
                LazyVGrid(columns: Self.columns, spacing: 4) {
                    ForEach(cells) { cell in
                        InboxMonthCell(
                            cell: cell,
                            selected: cell.iso != nil && cell.iso == selectedDay,
                            isToday: cell.iso == todayISO,
                            dots: dots(for: cell.iso),
                            onTap: { cell.iso.map { onSelectDay($0) } }
                        )
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(EvenTokens.paperCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1)
                    )
            )
            .accessibilityIdentifier("calendar-month-grid")
        }

        private var weekdayHeader: some View {
            HStack(spacing: 2) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 8.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(EvenTokens.stone)
                        .frame(maxWidth: .infinity)
                }
            }
        }

        private var weekdaySymbols: [String] {
            let calendar = Self.gridCalendar
            let symbols = calendar.veryShortWeekdaySymbols
            let shift = calendar.firstWeekday - 1
            return Array(symbols[shift...] + symbols[..<shift])
        }

        private var todayISO: String {
            InboxFormat.day.string(from: Date())
        }

        // MARK: - Grid model

        private var cells: [InboxMonthCellModel] {
            guard let anchor = InboxFormat.day.date(from: monthStart) else { return [] }
            let calendar = Self.gridCalendar
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)) ?? anchor
            guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }

            let weekday = calendar.component(.weekday, from: start)
            let leading = (weekday - calendar.firstWeekday + 7) % 7
            var out = (0 ..< leading).map { InboxMonthCellModel(id: "pad-lead-\($0)", day: nil, iso: nil) }
            for offset in 0 ..< range.count {
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
                let iso = InboxFormat.day.string(from: date)
                out.append(
                    InboxMonthCellModel(
                        id: iso,
                        day: calendar.component(.day, from: date),
                        iso: iso
                    )
                )
            }
            while out.count % 7 != 0 {
                out.append(InboxMonthCellModel(id: "pad-tail-\(out.count)", day: nil, iso: nil))
            }
            return out
        }

        /// At most three dots — a day that carries more says so with a plus.
        private func dots(for iso: String?) -> [Color] {
            guard let iso else { return [] }
            return items
                .filter { $0.dueOn == iso }
                .map { color(for: $0.ownerMemberId) }
        }

        private func color(for ownerMemberId: UUID) -> Color {
            if let me, ownerMemberId == me.id { return Color(hex: me.color.rgb) }
            if let partner, ownerMemberId == partner.id { return Color(hex: partner.color.rgb) }
            return EvenTokens.stone
        }
    }

    struct InboxMonthCellModel: Identifiable, Equatable {
        let id: String
        let day: Int?
        let iso: String?
    }

    struct InboxMonthCell: View {
        let cell: InboxMonthCellModel
        let selected: Bool
        let isToday: Bool
        let dots: [Color]
        let onTap: () -> Void

        var body: some View {
            VStack(spacing: 3) {
                if let day = cell.day {
                    Text("\(day)")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(selected ? EvenTokens.paperRaised : EvenTokens.espresso)
                        .frame(width: 26, height: 26)
                        .background(dayBackground)
                    dotRow
                } else {
                    Color.clear.frame(width: 26, height: 26)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityHidden(cell.day == nil)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        }

        @ViewBuilder
        private var dayBackground: some View {
            if selected {
                Circle().fill(EvenTokens.espresso)
            } else if isToday {
                Circle().stroke(EvenTokens.terracotta, lineWidth: 1.5)
            }
        }

        private var dotRow: some View {
            HStack(spacing: 2.5) {
                ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                }
                if dots.count > 3 {
                    Text("+")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(EvenTokens.stone)
                }
            }
            .frame(height: 5)
        }

        private var accessibilityLabel: String {
            guard let day = cell.day else { return "" }
            let count = dots.count
            let suffix = count == 0
                ? "nothing scheduled"
                : "\(count) item\(count == 1 ? "" : "s")"
            return "Day \(day), \(suffix)"
        }
    }

    #if DEBUG
        #Preview("Month grid") {
            InboxMonthGrid(
                monthStart: "2026-08-01",
                items: PreviewData.calendarMonth.items,
                selectedDay: "2026-08-08",
                me: PreviewData.ada,
                partner: PreviewData.umut,
                onSelectDay: { _ in }
            )
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .evenPaperBackground()
        }
    #endif
#endif
