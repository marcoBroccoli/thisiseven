import WidgetKit
import SwiftUI
import EvenCore

// MARK: - Shared bits

/// The Even wordmark used top-right on the paper cards.
private struct Wordmark: View {
    var size: CGFloat = 15
    var body: some View {
        Text("Even").font(WidgetFont.serif(size, .regular, italic: true)).foregroundStyle(WT.ink)
    }
}

private extension EvenWidgetSnapshot {
    var adaSide: Side { clay }
    var umutSide: Side { teal }
    func ownerName(_ item: UpNext) -> String {
        item.ownerColor == .clay ? clay.name : teal.name
    }
}

// MARK: - Small: Balance

struct BalanceSmallView: View {
    let snapshot: EvenWidgetSnapshot
    private let p = WidgetPalette.cream

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("THIS WEEK").caps(8).foregroundStyle(p.sub)
                Spacer()
                Wordmark()
            }
            BalanceBeam(snapshot: snapshot, palette: p).frame(maxHeight: .infinity)
            HStack(spacing: 5) {
                Circle().fill(WT.ada).frame(width: 8, height: 8)
                Text("\(snapshot.adaSide.share)")
                    .font(WidgetFont.serif(12, .semibold)).foregroundStyle(p.ink).monospacedDigit()
                Text("/").font(WidgetFont.serif(12)).foregroundStyle(p.sub)
                Text("\(snapshot.umutSide.share)")
                    .font(WidgetFont.serif(12, .semibold)).foregroundStyle(p.ink).monospacedDigit()
                Circle().fill(WT.umut).frame(width: 8, height: 8)
            }
        }
        .padding(14)
        .containerBackground(p.bg, for: .widget)
    }
}

struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvenBalance", provider: EvenProvider()) { entry in
            BalanceSmallView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Balance")
        .description("This week's balance beam.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Medium: Balance + Up Next

struct BalanceUpNextView: View {
    let snapshot: EvenWidgetSnapshot
    private let p = WidgetPalette.cream

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack { Text("BALANCE").caps(8).foregroundStyle(p.sub); Spacer() }
                BalanceBeam(snapshot: snapshot, palette: p).frame(maxHeight: .infinity)
                Text(Leader.copy(snapshot))
                    .font(WidgetFont.serif(13, .regular, italic: true))
                    .foregroundStyle(p.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 118)
            .overlay(alignment: .trailing) {
                Rectangle().fill(p.line).frame(width: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("UP NEXT").caps(8).foregroundStyle(p.sub)
                ForEach(snapshot.upcoming.prefix(2)) { item in
                    MediumRow(item: item, name: snapshot.ownerName(item), palette: p)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .containerBackground(p.bg, for: .widget)
    }
}

private struct MediumRow: View {
    let item: EvenWidgetSnapshot.UpNext
    let name: String
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 8) {
            OwnerChip(color: palette.member(item.ownerColor), initial: item.ownerInitial, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(WidgetFont.serif(14, .medium))
                    .foregroundStyle(palette.ink).lineLimit(1)
                Text(item.typeMeta).caps(8).foregroundStyle(palette.sub)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.when).caps(8)
                    .foregroundStyle(item.when == "TODAY" ? palette.ink : palette.sub)
                if let amount = item.amountCents {
                    Text(WidgetFormat.euros(amount))
                        .font(WidgetFont.serif(11.5, .medium)).foregroundStyle(palette.ink)
                        .monospacedDigit()
                }
            }
        }
    }
}

struct BalanceUpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvenBalanceUpNext", provider: EvenProvider()) { entry in
            BalanceUpNextView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Balance + Up Next")
        .description("The beam plus the next two things due.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Large: This Week

struct ThisWeekLargeView: View {
    let snapshot: EvenWidgetSnapshot
    private let p = WidgetPalette.cream

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("THIS WEEK · WK \(snapshot.weekIndex)").caps(9).foregroundStyle(p.sub)
                Spacer()
                Wordmark(size: 17)
            }

            HStack(alignment: .top, spacing: 14) {
                BalanceBeam(snapshot: snapshot, palette: p).frame(width: 96, height: 80)
                VStack(alignment: .leading, spacing: 8) {
                    Text(Leader.copy(snapshot) + ".")
                        .font(WidgetFont.serif(19, .regular, italic: true))
                        .foregroundStyle(p.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Circle().fill(WT.ada).frame(width: 6, height: 6)
                        Text("\(snapshot.adaSide.done) done").font(WidgetFont.sans(11)).foregroundStyle(p.sub)
                        Text("/").font(WidgetFont.serif(11)).foregroundStyle(p.sub)
                        Circle().fill(WT.umut.opacity(snapshot.hasPartner ? 1 : 0.4)).frame(width: 6, height: 6)
                        Text("\(snapshot.umutSide.done)").font(WidgetFont.sans(11)).foregroundStyle(p.sub)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("COMING UP").caps(9).foregroundStyle(p.sub)
                ForEach(snapshot.upcoming.prefix(4)) { item in
                    LargeRow(item: item, palette: p)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Rectangle().fill(p.line).frame(height: 1)
                HStack(spacing: 6) {
                    CalendarMark()
                    Text("On your shared Even calendar · \(snapshot.leftToday) due today")
                        .font(WidgetFont.sans(9.5)).foregroundStyle(p.sub)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .containerBackground(p.bg, for: .widget)
    }
}

/// A small calendar glyph with one ADA and one UMUT dot on top.
private struct CalendarMark: View {
    var body: some View {
        Image(systemName: "calendar")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(WT.sub)
            .overlay(alignment: .top) {
                HStack(spacing: 2) {
                    Circle().fill(WT.ada).frame(width: 2.5, height: 2.5)
                    Circle().fill(WT.umut).frame(width: 2.5, height: 2.5)
                }
                .offset(y: 1.5)
            }
    }
}

private struct LargeRow: View {
    let item: EvenWidgetSnapshot.UpNext
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 9) {
            OwnerChip(color: palette.member(item.ownerColor), initial: item.ownerInitial, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(WidgetFont.serif(14.5, .medium))
                    .foregroundStyle(palette.ink).lineLimit(1)
                Text(item.typeMeta).caps(8).foregroundStyle(palette.sub)
            }
            Spacer(minLength: 4)
            if item.gcal {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(palette.sub)
            }
            Text(item.when).caps(8.5)
                .foregroundStyle(item.when == "TODAY" ? palette.ink : palette.sub)
                .frame(width: 34, alignment: .trailing)
            Text(item.amountCents.map(WidgetFormat.euros) ?? "")
                .font(WidgetFont.serif(12, .medium)).foregroundStyle(palette.ink)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct ThisWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvenThisWeek", provider: EvenProvider()) { entry in
            ThisWeekLargeView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("This Week")
        .description("Balance, who did what, and what's coming up.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Small: Today (dark card)

struct TodaySmallView: View {
    let snapshot: EvenWidgetSnapshot
    private let p = WidgetPalette.dark

    private var yourTurn: Int {
        snapshot.upcoming.filter { $0.ownerColor == snapshot.clay.color }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TODAY").caps(8).foregroundStyle(p.sub)
                Spacer()
                OwnerChip(color: WT.ada, initial: snapshot.clay.initial, size: 16)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(snapshot.leftToday)")
                    .font(WidgetFont.serif(58, .medium)).foregroundStyle(WT.cream).monospacedDigit()
                Text("left")
                    .font(WidgetFont.serif(15, .regular, italic: true)).foregroundStyle(p.sub)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(WT.ada).frame(width: 6, height: 6)
                Text(caption).font(WidgetFont.sans(9.5)).foregroundStyle(WT.onDark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .containerBackground(p.bg, for: .widget)
    }

    private var caption: String {
        if snapshot.leftToday == 0 { return "All settled for today" }
        if yourTurn == 0 { return "None of them are yours" }
        return "Your turn on \(yourTurn) of them"
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvenToday", provider: EvenProvider()) { entry in
            TodaySmallView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Today")
        .description("How many household items are still due today.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Small: Up Next

struct UpNextSmallView: View {
    let snapshot: EvenWidgetSnapshot
    private let p = WidgetPalette.cream

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("UP NEXT").caps(8).foregroundStyle(p.sub)
                Spacer()
                if let item = snapshot.upcoming.first {
                    Text(item.when).caps(8).foregroundStyle(WT.ada)
                }
            }
            Spacer(minLength: 0)
            if let item = snapshot.upcoming.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(WidgetFont.serif(20, .medium)).foregroundStyle(p.ink)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(item.typeMeta).caps(8.5).foregroundStyle(p.sub)
                }
                Spacer(minLength: 0)
                HStack(alignment: .center) {
                    OwnerChip(color: p.member(item.ownerColor), initial: item.ownerInitial, size: 16)
                    Text(snapshot.ownerName(item)).font(WidgetFont.sans(10)).foregroundStyle(p.sub)
                    Spacer()
                    if let amount = item.amountCents {
                        Text(WidgetFormat.euros(amount))
                            .font(WidgetFont.serif(17, .medium)).foregroundStyle(p.ink).monospacedDigit()
                    }
                }
            } else {
                Spacer()
                Text("Nothing queued.")
                    .font(WidgetFont.serif(17, .regular, italic: true)).foregroundStyle(p.sub)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .containerBackground(p.bg, for: .widget)
    }
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "EvenUpNext", provider: EvenProvider()) { entry in
            UpNextSmallView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Up Next")
        .description("The next thing due, with owner and amount.")
        .supportedFamilies([.systemSmall])
    }
}
