import SwiftUI
import EvenCore

// Dated todos are shown as one shared schedule and are published to Google
// Calendar when the household connection is available.

struct CalendarView: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var displayedMonth = Date()
    @State private var selectedDay: Date? = Date()

    private var cal: Foundation.Calendar {
        var c = Foundation.Calendar.current
        c.firstWeekday = 2   // design: week starts Monday
        return c
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(kicker: "GOOGLE CALENDAR", title: "Schedule",
                             subtitle: "Dated todos live on the shared calendar.")
                sharedPill
                monthHeader
                dowRow
                monthGrid

                if monthIsEmpty {
                    emptyMonthCard
                } else if let day = selectedDay, cal.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
                    dayCard(day)
                } else {
                    Text("Tap a marked day to see what's due.")
                        .font(EvenFont.serif(13, italic: true))
                        .foregroundStyle(palette.sub)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }

                agendaSection
                googleCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
            .animation(.easeOut(duration: 0.2), value: selectedKey)
            .animation(.easeOut(duration: 0.25), value: model.calendarMonthItems)
        }
        .refreshable { await refreshSchedule() }
        .task(id: model.calendarRevision) { await refreshSchedule() }
        .onChange(of: monthKey) { _, _ in
            Task { await model.loadCalendar(month: displayedMonth) }
        }
    }

    // MARK: Date plumbing

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func key(_ date: Date) -> String { Self.dayFormat.string(from: date) }
    private var todayKey: String { key(Date()) }
    private var selectedKey: String? { selectedDay.map(key) }
    private var monthKey: String {
        let c = cal.dateComponents([.year, .month], from: displayedMonth)
        return "\(c.year ?? 0)-\(c.month ?? 0)"
    }

    private var itemsByDay: [String: [CalendarItem]] {
        Dictionary(grouping: model.calendarMonthItems, by: \.dueOn)
    }

    private var monthIsEmpty: Bool {
        let prefix = String(key(displayedMonth).prefix(7))
        return !model.calendarMonthItems.contains { $0.dueOn.hasPrefix(prefix) }
    }

    private var monthName: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        return f.string(from: displayedMonth)
    }

    // MARK: Header row

    @ViewBuilder
    private var sharedPill: some View {
        if model.calendarInfo?.shared == true {
            HStack {
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                    Text("SHARED · GOOGLE").capsLabel(8.5, tracking: 1.2)
                }
                .foregroundStyle(palette.sub)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
            }
            .padding(.top, 2)
        }
    }

    private var monthHeader: some View {
        HStack {
            stepButton("chevron.left") { step(-1) }
            Text(monthLabel)
                .font(EvenFont.serif(22, .medium, italic: true))
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
            stepButton("chevron.right") { step(1) }
        }
        .padding(.top, 6)
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(palette.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
    }

    private func step(_ direction: Int) {
        if let next = cal.date(byAdding: .month, value: direction, to: displayedMonth) {
            withAnimation(.easeOut(duration: 0.2)) { displayedMonth = next }
        }
    }

    private func refreshSchedule() async {
        await model.loadCalendar(month: displayedMonth)
        if model.calendarInfo?.shared == true {
            await model.syncCalendar()
            await model.loadCalendar(month: displayedMonth)
        }
    }

    // MARK: Grid

    private var dowRow: some View {
        HStack(spacing: 0) {
            ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { _, letter in
                Text(String(letter))
                    .capsLabel(9, tracking: 1)
                    .foregroundStyle(palette.sub)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var monthDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth),
              let dayCount = cal.range(of: .day, in: .month, for: displayedMonth)?.count
        else { return [] }
        let first = interval.start
        let leading = (cal.component(.weekday, from: first) + 5) % 7   // Mon = 0
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<dayCount {
            cells.append(cal.date(byAdding: .day, value: d, to: first))
        }
        return cells
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 50)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let k = key(day)
        let items = itemsByDay[k] ?? []
        let isSelected = selectedKey == k
        let isToday = todayKey == k

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: day))")
                    .font(EvenFont.serif(14.5))
                    .foregroundStyle(isSelected ? palette.card : palette.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isSelected ? palette.ink : .clear))
                    .overlay(Circle().stroke(isToday && !isSelected ? palette.ink : .clear, lineWidth: 1.2))
                HStack(spacing: 2.5) {
                    ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                        Circle()
                            .fill(ownerColor(item.ownerMemberId))
                            .frame(width: 4.5, height: 4.5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50, alignment: .top)
            .padding(.top, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty month

    private var emptyMonthCard: some View {
        VStack(spacing: 0) {
            Image(systemName: "calendar")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(palette.sub)
            Text("Nothing due in \(monthName) — yet.")
                .font(EvenFont.serif(17, italic: true))
                .foregroundStyle(palette.ink)
                .padding(.top, 4)
            Text("Add a due date to a todo and it will appear here.")
                .font(EvenFont.sans(11.5, .regular))
                .foregroundStyle(palette.sub)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 22)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(palette.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .padding(.top, 22)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Selected day

    private func dayCard(_ day: Date) -> some View {
        let items = itemsByDay[key(day)] ?? []
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(f.string(from: day).uppercased())
                    .capsLabel(9.5, tracking: 1.5)
                    .foregroundStyle(palette.sub)
                if todayKey == key(day) {
                    Text("TODAY")
                        .capsLabel(8, tracking: 1, weight: .bold)
                        .foregroundStyle(palette.card)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(palette.ink))
                }
            }
            .padding(.bottom, 2)

            if items.isEmpty {
                Text("Nothing due. Enjoy the blank space.")
                    .font(EvenFont.serif(14.5, italic: true))
                    .foregroundStyle(palette.sub)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            } else {
                ForEach(items) { item in
                    itemRow(item, titleSize: 15, chipSize: 20)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 5)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line, lineWidth: 1))
        .padding(.top, 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Agenda

    private var agendaSection: some View {
        let grouped = Dictionary(grouping: model.calendarUpcoming, by: \.dueOn)
        let days = grouped.keys.sorted()

        return VStack(alignment: .leading, spacing: 0) {
            Text("COMING UP — NEXT 7 DAYS")
                .capsLabel(9.5, tracking: 1.4)
                .foregroundStyle(palette.sub)
            if model.calendarUpcoming.isEmpty {
                Text("A quiet week ahead.")
                    .font(EvenFont.serif(13, italic: true))
                    .foregroundStyle(palette.sub)
                    .padding(.vertical, 12)
            }
            ForEach(days, id: \.self) { dayKey in
                ForEach(Array((grouped[dayKey] ?? []).enumerated()), id: \.element.id) { index, item in
                    agendaRow(item, dayKey: dayKey, showLabel: index == 0)
                }
            }
        }
        .padding(.top, 22)
    }

    private func agendaRow(_ item: CalendarItem, dayKey: String, showLabel: Bool) -> some View {
        HStack(spacing: 10) {
            Text(showLabel ? agendaDayLabel(dayKey) : "")
                .capsLabel(9, tracking: 0.7)
                .foregroundStyle(dayKey == todayKey ? palette.ink : palette.sub)
                .frame(width: 44, alignment: .leading)
            itemBody(item, titleSize: 14.5)
            amountText(item, size: 12)
            gcalLink(item)
            OwnerChip(member: model.member(item.ownerMemberId), palette: palette, size: 18)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { palette.faint.frame(height: 1) }
    }

    private func agendaDayLabel(_ dayKey: String) -> String {
        guard let date = Self.dayFormat.date(from: dayKey) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        return f.string(from: date).uppercased()
    }

    // MARK: Item rows

    private func itemRow(_ item: CalendarItem, titleSize: CGFloat, chipSize: CGFloat) -> some View {
        HStack(spacing: 10) {
            itemBody(item, titleSize: titleSize)
            amountText(item, size: 13)
            gcalLink(item)
            OwnerChip(member: model.member(item.ownerMemberId), palette: palette, size: chipSize)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { palette.faint.frame(height: 1) }
        .opacity(item.done == true ? 0.5 : 1)
    }

    private func itemBody(_ item: CalendarItem, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(EvenFont.serif(titleSize))
                .strikethrough(item.done == true, color: palette.ink)
                .foregroundStyle(palette.ink)
                .lineLimit(2)
            Text(metaLine(item))
                .capsLabel(8.5, tracking: 0.5)
                .foregroundStyle(palette.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaLine(_ item: CalendarItem) -> String {
        if item.kind == .task {
            return item.done == true ? "TODO · DONE" : "TODO"
        }
        let type: String
        switch item.category {
        case "bills": type = "BILL"
        case "appointments": type = "APPOINTMENT"
        case "subscriptions": type = "RENEWAL"
        case "admin": type = "ADMIN"
        default: type = "DRAFT"
        }
        return type == "DRAFT" ? "SUGGESTED TODO · REVIEW" : "\(type) · REVIEW"
    }

    @ViewBuilder
    private func amountText(_ item: CalendarItem, size: CGFloat) -> some View {
        if let cents = item.amountCents {
            Text(EvenFormat.euros(cents))
                .font(EvenFont.sans(size, .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
        }
    }

    @ViewBuilder
    private func gcalLink(_ item: CalendarItem) -> some View {
        if let urlString = item.googleEventUrl, let url = URL(string: urlString) {
            Link(destination: url) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.sub)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(palette.line, lineWidth: 1))
            }
        }
    }

    // MARK: Google footer

    private var ownerColorFallback: Color { palette.sub }

    private func ownerColor(_ id: UUID) -> Color {
        model.member(id).map { palette.member($0.color) } ?? ownerColorFallback
    }

    private var googleCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(palette.ink)
                Circle().fill(palette.clay).frame(width: 4, height: 4).offset(x: -3, y: 2)
                Circle().fill(palette.teal).frame(width: 4, height: 4).offset(x: 4, y: 5)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("This schedule lives in Google Calendar.")
                    .font(EvenFont.serif(14.5))
                    .foregroundStyle(palette.ink)
                Text(googleCardBody)
                    .font(EvenFont.sans(11, .regular))
                    .foregroundStyle(palette.sub)
                if let urlString = model.calendarInfo?.shareUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Text("SUBSCRIBE IN GOOGLE CALENDAR")
                            .capsLabel(9, tracking: 1)
                            .foregroundStyle(palette.clay)
                            .underline()
                    }
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(palette.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .padding(.top, 20)
    }

    private var googleCardBody: String {
        if model.calendarInfo?.shared == true {
            return "Every dated todo is published to this shared calendar."
        }
        if model.googleStatus?.connected == true {
            return "Your first dated todo creates the shared calendar — the subscribe link appears here."
        }
        return "Connect Google from Todos to publish a shared household calendar."
    }
}
