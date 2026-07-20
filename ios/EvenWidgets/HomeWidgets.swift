import WidgetKit
import SwiftUI
import EvenCore

// MARK: - Small: Balance

struct BalanceSmallView: View {
    let snapshot: EvenWidgetSnapshot
    private let p = WidgetPalette.paper

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text("THIS WEEK").caps(9, tracking: 1.8).foregroundStyle(p.sub)
                Spacer()
                Text("WK \(snapshot.weekIndex)").caps(9, tracking: 1.8).foregroundStyle(p.sub)
            }
            BalanceBeam(snapshot: snapshot, palette: p).frame(maxHeight: .infinity)
            SharePair(snapshot: snapshot, palette: p)
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
    private let p = WidgetPalette.paper

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("THIS WEEK").caps(8.5, tracking: 1.8).foregroundStyle(p.sub)
                BalanceBeam(snapshot: snapshot, palette: p).frame(maxHeight: .infinity)
                SharePair(snapshot: snapshot, palette: p)
            }
            .frame(width: 138)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("UP NEXT").caps(8.5, tracking: 1.8).foregroundStyle(p.sub)
                    Spacer()
                    LeaderTick(color: p.member(leaderColor))
                }
                ForEach(snapshot.upcoming.prefix(2)) { item in
                    UpNextRow(item: item, palette: p)
                }
                Spacer(minLength: 0)
                Text(snapshot.leader)
                    .font(WidgetFont.serif(11).italic())
                    .foregroundStyle(p.sub)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .containerBackground(p.bg, for: .widget)
    }

    private var leaderColor: MemberColor {
        snapshot.clay.share >= snapshot.teal.share ? snapshot.clay.color : snapshot.teal.color
    }
}

/// The little leader tick echoing the design's leader-line accent.
struct LeaderTick: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
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
    private let p = WidgetPalette.paper

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("THIS WEEK").caps(10, tracking: 2).foregroundStyle(p.sub)
                Spacer()
                Text("WK \(snapshot.weekIndex)").caps(10, tracking: 2).foregroundStyle(p.sub)
            }

            HStack(spacing: 16) {
                BalanceBeam(snapshot: snapshot, palette: p)
                    .frame(width: 168, height: 150)
                VStack(alignment: .leading, spacing: 8) {
                    SharePair(snapshot: snapshot, palette: p)
                    doneRow(snapshot.clay)
                    doneRow(snapshot.teal, muted: !snapshot.hasPartner)
                    Spacer(minLength: 0)
                    Text(snapshot.leader)
                        .font(WidgetFont.serif(12).italic())
                        .foregroundStyle(p.sub)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(p.line)

            VStack(alignment: .leading, spacing: 6) {
                Text("COMING UP").caps(9, tracking: 1.8).foregroundStyle(p.sub)
                ForEach(snapshot.upcoming.prefix(4)) { item in
                    UpNextRow(item: item, palette: p)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Text("\(snapshot.leftToday) due today")
                    .font(WidgetFont.serif(12, .medium))
                    .foregroundStyle(p.ink)
            }
        }
        .padding(16)
        .containerBackground(p.bg, for: .widget)
    }

    private func doneRow(_ member: EvenWidgetSnapshot.Side, muted: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle().fill(muted ? p.sub : p.member(member.color)).frame(width: 6, height: 6)
            Text(member.name).font(WidgetFont.sans(11, .semibold)).foregroundStyle(p.ink)
            Spacer()
            Text("\(member.done) done").caps(9, tracking: 1).foregroundStyle(p.sub)
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

// MARK: - Small: Today

struct TodaySmallView: View {
    let snapshot: EvenWidgetSnapshot
    private let p = WidgetPalette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY").caps(10, tracking: 2.2).foregroundStyle(p.sub)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(snapshot.leftToday)")
                    .font(WidgetFont.serif(64, .medium))
                    .foregroundStyle(p.ink)
                    .monospacedDigit()
                Text("left")
                    .font(WidgetFont.serif(20).italic())
                    .foregroundStyle(p.sub)
            }
            Spacer()
            Text(snapshot.leftToday == 0 ? "All settled." : "due today")
                .caps(9, tracking: 1.6).foregroundStyle(p.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .containerBackground(p.bg, for: .widget)
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
    private let p = WidgetPalette.paper

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UP NEXT").caps(10, tracking: 2).foregroundStyle(p.sub)
            Spacer(minLength: 0)
            if let item = snapshot.upcoming.first {
                Text(item.title)
                    .font(WidgetFont.serif(19, .medium))
                    .foregroundStyle(p.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Circle().fill(p.member(item.ownerColor)).frame(width: 6, height: 6)
                    Text(item.ownerInitial).caps(9, tracking: 1).foregroundStyle(p.sub)
                    if item.gcal {
                        Image(systemName: "calendar").font(.system(size: 8)).foregroundStyle(p.sub)
                    }
                    Text(item.when).caps(9, tracking: 1).foregroundStyle(p.sub)
                }
                Spacer(minLength: 0)
                if let amount = item.amountCents {
                    Text(WidgetFormat.euros(amount))
                        .font(WidgetFont.serif(22, .medium))
                        .foregroundStyle(p.member(item.ownerColor))
                }
            } else {
                Spacer()
                Text("Nothing queued.")
                    .font(WidgetFont.serif(17).italic())
                    .foregroundStyle(p.sub)
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
