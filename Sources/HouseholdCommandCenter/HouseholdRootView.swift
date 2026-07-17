import SwiftUI
import HouseholdCore

struct HouseholdRootView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        ZStack {
            AppPalette.canvas
                .ignoresSafeArea()

            MobileAppShell(store: store)
        }
        .frame(minWidth: 390, idealWidth: 430, maxWidth: .infinity, minHeight: 720, idealHeight: 844, maxHeight: .infinity)
    }
}

private enum AppPalette {
    static let canvas = Color(red: 0.933, green: 0.925, blue: 0.906)
    static let surface = Color.white
    static let ink = Color(red: 0.086, green: 0.086, blue: 0.086)
    static let muted = Color.black.opacity(0.48)
    static let purple = Color(red: 0.420, green: 0.373, blue: 0.780)
    static let purpleDark = Color(red: 0.290, green: 0.247, blue: 0.569)
    static let purpleSoft = Color(red: 0.949, green: 0.937, blue: 0.988)
    static let teal = Color(red: 0.227, green: 0.541, blue: 0.510)
    static let red = Color(red: 0.702, green: 0.153, blue: 0.122)
    static let redSoft = Color(red: 0.984, green: 0.906, blue: 0.898)
    static let amber = Color(red: 0.890, green: 0.604, blue: 0.122)
    static let amberText = Color(red: 0.604, green: 0.376, blue: 0.031)
    static let amberSoft = Color(red: 0.984, green: 0.937, blue: 0.859)
    static let line = Color.black.opacity(0.07)
}

private struct MobileAppShell: View {
    @ObservedObject var store: DemoHouseholdStore
    @State private var isPresentingQuickAdd = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                MainContentView(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MobileTabBar(store: store)
            }

            Button {
                store.beginManualItem()
                isPresentingQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .bold))
                    .frame(width: 52, height: 52)
                    .foregroundStyle(Color.white)
                    .background(AppPalette.purple, in: Circle())
                    .shadow(color: AppPalette.purple.opacity(0.28), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .help("Add a household item")
            .padding(.trailing, 18)
            .padding(.bottom, 74)
        }
        .frame(maxWidth: 430, maxHeight: .infinity)
        .background(AppPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 34, x: 0, y: 18)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .sheet(isPresented: $isPresentingQuickAdd) {
            ManualItemSheet(store: store, isPresented: $isPresentingQuickAdd)
        }
    }
}

private struct MobileTabBar: View {
    @ObservedObject var store: DemoHouseholdStore

    private let tabs: [HouseholdSection] = [.today, .inbox, .bills, .reminders, .areas]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { section in
                Button {
                    store.selectedSection = section
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: section.mobileSystemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 24)
                        Text(section.mobileTitle)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isSelected(section) ? AppPalette.purple : Color.black.opacity(0.40))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppPalette.line)
                .frame(height: 1)
        }
    }

    private func isSelected(_ section: HouseholdSection) -> Bool {
        if store.selectedSection == section {
            return true
        }
        if section == .areas {
            return store.selectedSection == .settings || store.selectedSection == .review || store.selectedSection == .banking
        }
        return false
    }
}

private struct HeaderView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Household Command Center")
                    .font(.system(size: 22, weight: .semibold))
                Text(store.syncMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            MetricPill(title: "Urgent", value: store.urgentCount)
            MetricPill(title: "Replies", value: store.replyNeededCount)
            MetricPill(title: "Bills", value: store.dashboard.billsDueSoon.count)
            MetricPill(title: "Sync", value: store.model.changedExternallyCount + store.model.retryRequiredCount)

            Button {
                Task { await store.importGmailLabel() }
            } label: {
                Label("Discover", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .help("Discover likely household emails from Gmail")

            Button {
                Task { await store.checkCalendarSync() }
            } label: {
                Label("Calendar", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Check approved Google Calendar events for external changes")
        }
        .padding(20)
    }
}

private struct NavigationRail: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Household")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 18)

            ForEach(HouseholdSection.allCases) { section in
                Button {
                    store.selectedSection = section
                } label: {
                    Label(section.rawValue, systemImage: section.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(store.selectedSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Text("Source of truth")
                    .font(.caption.weight(.semibold))
                Text("Approved work becomes Google Calendar events. This app stores approval context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct MainContentView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        switch store.selectedSection {
        case .today:
            TodayView(store: store)
        case .inbox:
            InboxWorkspace(store: store)
        case .bills:
            BillsView(store: store)
        case .reminders:
            RemindersView(store: store)
        case .review:
            WeeklyReviewView(store: store)
        case .banking:
            BankingView(store: store)
        case .areas:
            AreasView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }
}

private struct TodayView: View {
    @ObservedObject var store: DemoHouseholdStore
    @State private var selectedFilter: TodayFilter = .all

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                TodayHeader(store: store, totalCount: totalCount)
                if let draft = store.nextActionDraft {
                    NextActionCard(
                        store: store,
                        draft: draft,
                        intelligence: store.intelligence(for: draft)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
                TodayMVPCard(store: store)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                TodayFilterRow(
                    selectedFilter: $selectedFilter,
                    sections: store.todaySections,
                    totalCount: totalCount
                )

                if filteredSections.isEmpty {
                    MobileEmptyState(
                        title: "Today is clear",
                        detail: "Discover Gmail emails or add a manual item when new household work arrives.",
                        systemImage: "checkmark.circle"
                    )
                    .padding(.top, 28)
                } else {
                    ForEach(filteredSections) { section in
                        TodaySectionBlock(section: section, store: store)
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(AppPalette.canvas)
    }

    private var totalCount: Int {
        store.todaySections.reduce(0) { $0 + $1.drafts.count }
    }

    private var filteredSections: [TodayReviewSection] {
        store.todaySections.compactMap { section in
            guard selectedFilter.includes(section) else { return nil }
            return section
        }
    }
}

private struct TodayHeader: View {
    @ObservedObject var store: DemoHouseholdStore
    var totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                    Text("\(todayText) · \(totalCount) need you")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                OwnerAvatarStack(members: store.household.members)
                    .padding(.top, 3)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await store.importGmailLabel() }
                } label: {
                    Label("Discover", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(MobilePrimaryButtonStyle())

                Button {
                    Task { await store.checkCalendarSync() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(MobileIconButtonStyle())
                .help("Check approved Google Calendar events for external changes")
            }

            Text(store.syncMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var todayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}

private struct NextActionCard: View {
    @ObservedObject var store: DemoHouseholdStore
    var draft: InboxDraft
    var intelligence: EmailIntelligenceResult

    private var readiness: CalendarReadiness {
        store.calendarReadiness(for: draft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Next up", systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppPalette.purpleDark)
                Spacer()
                UrgencyBadge(urgency: intelligence.urgency)
            }

            Text(draft.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(2)

            Text(nextActionDetail)
                .font(.system(size: 13))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button(action: performPrimaryAction) {
                    Label(primaryActionTitle, systemImage: primaryActionIcon)
                }
                .buttonStyle(MobilePrimaryButtonStyle())

                Button {
                    store.selectDraft(id: draft.id)
                    store.selectedSection = .inbox
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(MobileIconButtonStyle())
                .help("Open full item details")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppPalette.purple.opacity(0.18), lineWidth: 1)
        }
    }

    private var nextActionDetail: String {
        if draft.status == .calendarRetryRequired || draft.status == .calendarUpdateRequired || draft.status == .changedExternally {
            return readiness.detail
        }

        return intelligence.summary
    }

    private var primaryActionTitle: String {
        switch draft.status {
        case .calendarRetryRequired:
            "Retry"
        case .calendarUpdateRequired:
            "Sync Calendar"
        case .changedExternally:
            "Review change"
        case .pendingApproval where readiness.canApproveToCalendar:
            "Schedule"
        default:
            intelligence.primaryAction == .reply || intelligence.primaryAction == .scheduleAndReply || intelligence.primaryAction == .payAndReply
                ? "Write reply"
                : "Review"
        }
    }

    private var primaryActionIcon: String {
        switch draft.status {
        case .calendarRetryRequired:
            "arrow.clockwise"
        case .calendarUpdateRequired:
            "arrow.triangle.2.circlepath"
        case .pendingApproval where readiness.canApproveToCalendar:
            "calendar.badge.plus"
        case .changedExternally:
            "exclamationmark.arrow.triangle.2.circlepath"
        default:
            intelligence.primaryAction == .reply || intelligence.primaryAction == .scheduleAndReply || intelligence.primaryAction == .payAndReply
                ? "arrowshape.turn.up.left"
                : "checklist"
        }
    }

    private func performPrimaryAction() {
        store.selectDraft(id: draft.id)

        switch draft.status {
        case .calendarRetryRequired:
            Task { await store.retrySelectedCalendarWrite() }
        case .calendarUpdateRequired:
            Task { await store.syncSelectedCalendarUpdate() }
        case .pendingApproval where readiness.canApproveToCalendar:
            Task { await store.approveSelectedDraft() }
        default:
            store.selectedSection = .inbox
        }
    }
}

private struct TodayMVPCard: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week's MVP")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                Spacer()
                Text(mvpLeadText)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(AppPalette.purpleDark)

            GeometryReader { proxy in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(AppPalette.purple)
                        .frame(width: proxy.size.width * firstShare)
                    Rectangle()
                        .fill(AppPalette.teal)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 10)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            HStack {
                HStack(spacing: 6) {
                    OwnerAvatar(initial: firstInitial, color: AppPalette.purple, size: 18, fontSize: 10)
                    Text("\(firstHandled) handled")
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("\(secondHandled) handled")
                        .font(.system(size: 13, weight: .semibold))
                    OwnerAvatar(initial: secondInitial, color: AppPalette.teal, size: 18, fontSize: 10)
                }
            }
            .foregroundStyle(AppPalette.ink)
        }
        .padding(16)
        .background(AppPalette.purpleSoft)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppPalette.purple.opacity(0.15), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var openDrafts: [InboxDraft] {
        store.model.drafts.filter { !(($0.triageState?.isClosed) ?? false) }
    }

    private var firstMemberID: UUID? { store.household.members.first?.id }
    private var secondMemberID: UUID? { store.household.members.dropFirst().first?.id }

    private var firstHandled: Int {
        max(openDrafts.filter { $0.ownerID == firstMemberID }.count + store.model.approvedCount, 1)
    }

    private var secondHandled: Int {
        max(openDrafts.filter { $0.ownerID == secondMemberID }.count + store.model.drafts.filter { $0.status == .rejected }.count, 1)
    }

    private var firstShare: CGFloat {
        CGFloat(firstHandled) / CGFloat(max(firstHandled + secondHandled, 1))
    }

    private var mvpLeadText: String {
        let lead = abs(firstHandled - secondHandled)
        guard lead > 0 else { return "Tied today" }
        let leader = firstHandled >= secondHandled ? firstInitial : secondInitial
        return "\(leader) leads by \(lead)"
    }

    private var firstInitial: String {
        store.household.members.first.map(initial(for:)) ?? "J"
    }

    private var secondInitial: String {
        store.household.members.dropFirst().first.map(initial(for:)) ?? "M"
    }
}

private enum TodayFilter: String, CaseIterable, Identifiable {
    case all
    case overdue
    case dueToday
    case replies
    case waiting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .overdue: "Overdue"
        case .dueToday: "Due today"
        case .replies: "Replies"
        case .waiting: "Waiting"
        }
    }

    func includes(_ section: TodayReviewSection) -> Bool {
        switch self {
        case .all:
            true
        case .overdue:
            section.title == "Overdue"
        case .dueToday:
            section.title == "Due Today"
        case .replies:
            section.title == "Needs Reply"
        case .waiting:
            section.title == "Waiting"
        }
    }

    func count(in sections: [TodayReviewSection], totalCount: Int) -> Int {
        if self == .all { return totalCount }
        return sections.filter(includes).reduce(0) { $0 + $1.drafts.count }
    }

    var colors: (foreground: Color, background: Color) {
        switch self {
        case .all:
            (Color.white, AppPalette.ink)
        case .overdue:
            (AppPalette.red, AppPalette.redSoft)
        case .dueToday:
            (AppPalette.amberText, AppPalette.amberSoft)
        case .replies:
            (AppPalette.purple, AppPalette.purpleSoft)
        case .waiting:
            (Color.black.opacity(0.50), Color.black.opacity(0.06))
        }
    }
}

private struct TodayFilterRow: View {
    @Binding var selectedFilter: TodayFilter
    var sections: [TodayReviewSection]
    var totalCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TodayFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text("\(filter.title) · \(filter.count(in: sections, totalCount: totalCount))")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .foregroundStyle(labelColor(for: filter))
                            .background(backgroundColor(for: filter), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }

    private func labelColor(for filter: TodayFilter) -> Color {
        selectedFilter == filter ? Color.white : filter.colors.foreground
    }

    private func backgroundColor(for filter: TodayFilter) -> Color {
        selectedFilter == filter ? selectedBackground(for: filter) : filter.colors.background
    }

    private func selectedBackground(for filter: TodayFilter) -> Color {
        switch filter {
        case .all:
            AppPalette.ink
        case .overdue:
            AppPalette.red
        case .dueToday:
            AppPalette.amber
        case .replies:
            AppPalette.purple
        case .waiting:
            Color.black.opacity(0.52)
        }
    }
}

private struct TodaySectionBlock: View {
    var section: TodayReviewSection
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(sectionDisplayTitle)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                Spacer()
                Text("\(section.drafts.count)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(sectionAccent)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)

            VStack(spacing: 8) {
                ForEach(section.drafts) { draft in
                    TodayDraftRow(
                        draft: draft,
                        sectionTitle: section.title,
                        accent: sectionAccent,
                        store: store
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var sectionDisplayTitle: String {
        section.title == "Waiting" ? "Waiting on" : section.title
    }

    private var sectionAccent: Color {
        todayAccentColor(for: section.title)
    }
}

private struct TodayDraftRow: View {
    var draft: InboxDraft
    var sectionTitle: String
    var accent: Color
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        Button {
            store.selectDraft(id: draft.id)
            store.selectedSection = .inbox
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let areaName {
                            Text(areaName)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .foregroundStyle(chipForeground)
                                .background(chipBackground, in: Capsule())
                        }
                        if let timingText {
                            Text(timingText)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.42))
                        }
                    }

                    Text(draft.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)

                    Text(detailLine)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.52))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                trailingAction
            }
            .padding(.vertical, 12)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 4)
                    .padding(.vertical, 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppPalette.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailingAction: some View {
        switch sectionTitle {
        case "Overdue", "Calendar Attention":
            VStack(spacing: 6) {
                Button {
                    store.selectDraft(id: draft.id)
                    Task { await store.approveSelectedDraft() }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(TodayCircleButtonStyle(foreground: AppPalette.purple, background: AppPalette.purpleSoft))

                Button {
                    store.selectDraft(id: draft.id)
                    store.rejectSelectedDraft()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(TodayCircleButtonStyle(foreground: Color.black.opacity(0.45), background: Color.black.opacity(0.05)))
            }
        case "Due Today":
            if let owner = store.household.member(withID: draft.ownerID) {
                OwnerAvatar(initial: initial(for: owner), color: ownerColor(for: owner, in: store.household), size: 32, fontSize: 12)
            } else {
                Circle()
                    .stroke(Color.black.opacity(0.22), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 32, height: 32)
            }
        case "Needs Reply":
            Button {
                store.selectDraft(id: draft.id)
                store.selectedSection = .inbox
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(TodayCircleButtonStyle(foreground: AppPalette.purple, background: AppPalette.purpleSoft))
        default:
            Text(waitingAgeText)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.35))
        }
    }

    private var areaName: String? {
        store.household.area(withID: draft.areaID)?.name
    }

    private var timingText: String? {
        if sectionTitle == "Waiting" {
            return relativeDays(from: draft.source.receivedAt, suffix: "waiting")
        }

        guard let dueDate = draft.dueDate else {
            return sectionTitle == "Needs Reply" ? nil : "No due date"
        }

        switch sectionTitle {
        case "Overdue":
            return relativeDays(from: dueDate, suffix: "late")
        case "Due Today":
            return nil
        default:
            return shortRelativeDate(dueDate)
        }
    }

    private var detailLine: String {
        var pieces: [String] = []
        if let amount = draft.amount {
            pieces.append(amount.description)
        }
        if let owner = store.household.member(withID: draft.ownerID) {
            pieces.append(owner.displayName)
        } else if sectionTitle == "Due Today" {
            pieces.append("unassigned")
        }
        if sectionTitle == "Needs Reply" {
            pieces.append(replyDetail)
        } else {
            pieces.append(draft.source.from)
        }
        return pieces.joined(separator: " · ")
    }

    private var replyDetail: String {
        if let status = draft.replyStatus, status == .drafted || status == .copied || status == .openedInGmail {
            return "Draft reply ready to review"
        }
        return "Reply needed"
    }

    private var chipForeground: Color {
        switch sectionTitle {
        case "Overdue":
            return AppPalette.red
        case "Due Today":
            return AppPalette.amberText
        case "Needs Reply":
            return AppPalette.purple
        default:
            return Color.black.opacity(0.50)
        }
    }

    private var chipBackground: Color {
        switch sectionTitle {
        case "Overdue":
            return AppPalette.redSoft
        case "Due Today":
            return AppPalette.amberSoft
        case "Needs Reply":
            return AppPalette.purpleSoft
        default:
            return Color.black.opacity(0.06)
        }
    }

    private var waitingAgeText: String {
        relativeDays(from: draft.source.receivedAt, suffix: nil) ?? ""
    }
}

private struct OwnerAvatarStack: View {
    var members: [HouseholdMember]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(Array(members.prefix(2).enumerated()), id: \.element.id) { index, member in
                OwnerAvatar(
                    initial: initial(for: member),
                    color: index == 0 ? AppPalette.purple : AppPalette.teal,
                    size: 32,
                    fontSize: 13
                )
                .overlay {
                    Circle()
                        .stroke(AppPalette.surface, lineWidth: 2)
                }
            }
        }
    }
}

private struct OwnerAvatar: View {
    var initial: String
    var color: Color
    var size: CGFloat
    var fontSize: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

private struct MobileEmptyState: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppPalette.purple)
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
            Text(detail)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
    }
}

private struct MobilePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AppPalette.purple.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MobileIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppPalette.ink.opacity(0.60))
            .padding(9)
            .background(Color.black.opacity(configuration.isPressed ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TodayCircleButtonStyle: ButtonStyle {
    var foreground: Color
    var background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.72 : 1))
            .frame(width: 30, height: 30)
            .background(background.opacity(configuration.isPressed ? 0.72 : 1), in: Circle())
    }
}

private func todayAccentColor(for title: String) -> Color {
    switch title {
    case "Calendar Attention":
        AppPalette.purple
    case "Overdue":
        AppPalette.red
    case "Due Today":
        AppPalette.amber
    case "Needs Reply":
        AppPalette.purple
    default:
        Color.black.opacity(0.18)
    }
}

private func relativeDays(from date: Date, suffix: String?) -> String? {
    let start = Calendar.current.startOfDay(for: date)
    let today = Calendar.current.startOfDay(for: Date())
    let days = abs(Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0)
    guard days > 0 else { return "today" }
    let base = "\(days)d"
    guard let suffix else { return base }
    return "\(days) day\(days == 1 ? "" : "s") \(suffix)"
}

private func shortRelativeDate(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
        return "today"
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
}

private func initial(for member: HouseholdMember) -> String {
    String(member.displayName.prefix(1)).uppercased()
}

private func ownerColor(for member: HouseholdMember, in household: HouseholdContext) -> Color {
    household.members.first?.id == member.id ? AppPalette.purple : AppPalette.teal
}

private struct InboxWorkspace: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Inbox")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                        Text(store.isGoogleConnected ? "Live Gmail discovery" : "Demo discovery")
                            .font(.system(size: 14))
                            .foregroundStyle(AppPalette.muted)
                    }
                    Spacer()
                    Button {
                        Task { await store.importGmailLabel() }
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .buttonStyle(MobileIconButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                if let draft = store.selectedDraft {
                    MobileDraftEditor(
                        store: store,
                        draft: draft,
                        intelligence: store.intelligence(for: draft)
                    )
                    .padding(.horizontal, 16)
                } else {
                    MobileEmptyState(
                        title: "No draft selected",
                        detail: "Discover Gmail emails or create a manual item.",
                        systemImage: "tray"
                    )
                }

                OrganizedDraftList(store: store)
                    .padding(.bottom, 18)
            }
        }
        .background(AppPalette.canvas)
    }
}

private struct MobileDraftEditor: View {
    @ObservedObject var store: DemoHouseholdStore
    var draft: InboxDraft
    var intelligence: EmailIntelligenceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review draft")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(AppPalette.purple)
                    Text(draft.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)
                    Text(draft.source.from)
                        .font(.system(size: 13))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                }
                Spacer()
                StatusBadge(status: draft.status)
            }

            EmailIntelligencePanel(store: store, draft: draft, intelligence: intelligence)
            CalendarApprovalPanel(store: store, draft: draft, readiness: store.calendarReadiness(for: draft))
            DailyActionPanel(store: store, draft: draft)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: Binding(
                    get: { store.titleDraft },
                    set: store.updateSelectedTitle
                ))
                .textFieldStyle(.roundedBorder)

                DatePicker("Due", selection: Binding(
                    get: { store.dueDateDraft },
                    set: store.updateSelectedDueDate
                ), displayedComponents: [.date, .hourAndMinute])

                TextField("Amount", text: Binding(
                    get: { store.amountDraft },
                    set: store.updateSelectedAmount
                ))
                .textFieldStyle(.roundedBorder)

                Picker("Owner", selection: Binding(
                    get: { draft.ownerID?.uuidString ?? "" },
                    set: { store.updateSelectedOwner(UUID(uuidString: $0)) }
                )) {
                    Text("Unassigned").tag("")
                    ForEach(store.household.members) { member in
                        Text(member.displayName).tag(member.id.uuidString)
                    }
                }

                Picker("Area", selection: Binding(
                    get: { draft.areaID?.uuidString ?? "" },
                    set: { store.updateSelectedArea(UUID(uuidString: $0)) }
                )) {
                    Text("No area").tag("")
                    ForEach(store.household.areas) { area in
                        Text(area.name).tag(area.id.uuidString)
                    }
                }
            }
            .padding(14)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppPalette.line, lineWidth: 1)
            }

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    store.rejectSelectedDraft()
                } label: {
                    Label("Reject", systemImage: "xmark")
                }
                .disabled(draft.status == .approved)

                Button {
                    Task { await store.approveSelectedDraft() }
                } label: {
                    Label(draft.status == .calendarUpdateRequired ? "Sync Calendar" : "Approve", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(MobilePrimaryButtonStyle())
                .disabled(!store.calendarReadiness(for: draft).canApproveToCalendar)
            }
        }
        .padding(14)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.line, lineWidth: 1)
        }
    }
}

private struct InboxSidebar: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Organized Inbox", systemImage: "tray.full")
                    .font(.headline)
                Spacer()
                Text(store.isGoogleConnected ? "Live Gmail" : store.gmailLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

                OrganizedDraftList(store: store)
        }
    }
}

private struct OrganizedDraftList: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(store.triageBuckets) { bucket in
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(bucket.title) \(bucket.drafts.count)", systemImage: bucket.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)

                    ForEach(bucket.drafts) { draft in
                        Button {
                            store.selectDraft(id: draft.id)
                            store.selectedSection = .inbox
                        } label: {
                            InboxRow(
                                draft: draft,
                                household: store.household,
                                intelligence: store.intelligence(for: draft)
                            )
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(store.model.selectedDraftID == draft.id ? AppPalette.purpleSoft : AppPalette.surface)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppPalette.line, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct InboxRow: View {
    var draft: InboxDraft
    var household: HouseholdContext
    var intelligence: EmailIntelligenceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(draft.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let triageState = draft.triageState, triageState != .active {
                    TriageBadge(state: triageState)
                }
                if let replyStatus = draft.replyStatus, replyStatus != ReplyWorkflowStatus.none {
                    ReplyStatusBadge(status: replyStatus)
                }
                StatusBadge(status: draft.status)
            }

            Text(draft.source.from)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                if let dueDate = draft.dueDate {
                    Label(shortDate(dueDate), systemImage: "calendar")
                }
                if let amount = draft.amount {
                    Label(amount.description, systemImage: "creditcard")
                }
                if let owner = household.member(withID: draft.ownerID) {
                    Label(owner.displayName, systemImage: "person")
                }
                if let area = household.area(withID: draft.areaID) {
                    Label(area.name, systemImage: "folder")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                UrgencyBadge(urgency: intelligence.urgency)
                ForEach(intelligence.tags.prefix(3), id: \.self) { tag in
                    Text(tag.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct DraftDetailView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        Group {
            if let draft = store.selectedDraft {
                DraftDetailContent(
                    store: store,
                    draft: draft,
                    intelligence: store.intelligence(for: draft)
                )
            } else {
                ContentUnavailableView("No Draft Selected", systemImage: "tray", description: Text("Discover Gmail emails or create a manual item."))
            }
        }
    }
}

private struct DraftDetailContent: View {
    @ObservedObject var store: DemoHouseholdStore
    var draft: InboxDraft
    var intelligence: EmailIntelligenceResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Approval Draft")
                            .font(.title2.weight(.semibold))
                        Text("Imported from \(draft.source.from)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(status: draft.status)
                }

                EmailIntelligencePanel(store: store, draft: draft, intelligence: intelligence)
                CalendarApprovalPanel(store: store, draft: draft, readiness: store.calendarReadiness(for: draft))
                DailyActionPanel(store: store, draft: draft)

                Form {
                    TextField("Title", text: Binding(
                        get: { store.titleDraft },
                        set: store.updateSelectedTitle
                    ))

                    DatePicker("Due date", selection: Binding(
                        get: { store.dueDateDraft },
                        set: store.updateSelectedDueDate
                    ), displayedComponents: [.date, .hourAndMinute])

                    TextField("Amount", text: Binding(
                        get: { store.amountDraft },
                        set: store.updateSelectedAmount
                    ))

                    Picker("Owner", selection: Binding(
                        get: { draft.ownerID?.uuidString ?? "" },
                        set: { store.updateSelectedOwner(UUID(uuidString: $0)) }
                    )) {
                        Text("Unassigned").tag("")
                        ForEach(store.household.members) { member in
                            Text(member.displayName).tag(member.id.uuidString)
                        }
                    }

                    Picker("Area", selection: Binding(
                        get: { draft.areaID?.uuidString ?? "" },
                        set: { store.updateSelectedArea(UUID(uuidString: $0)) }
                    )) {
                        Text("No area").tag("")
                        ForEach(store.household.areas) { area in
                            Text(area.name).tag(area.id.uuidString)
                        }
                    }
                }
                .formStyle(.grouped)

                SourceEvidenceView(draft: draft)

                HStack {
                    Button(role: .destructive) {
                        store.rejectSelectedDraft()
                    } label: {
                        Label("Reject", systemImage: "xmark.circle")
                    }
                    .disabled(draft.status == .approved)

                    Spacer()

                    Button {
                        Task { await store.approveSelectedDraft() }
                    } label: {
                        if draft.status == .calendarUpdateRequired {
                            Label("Sync Calendar", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Approve to Calendar", systemImage: "calendar.badge.plus")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.calendarReadiness(for: draft).canApproveToCalendar)
                    .help(store.calendarReadiness(for: draft).detail)
                }
            }
            .padding(24)
        }
    }
}

private struct CalendarApprovalPanel: View {
    @ObservedObject var store: DemoHouseholdStore
    var draft: InboxDraft
    var readiness: CalendarReadiness

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Calendar")
                        .font(.headline)
                    CalendarReadinessBadge(state: readiness.state)
                }
                Text(readiness.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label(reminderText(readiness.recommendedReminderMinutesBefore), systemImage: "bell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if draft.googleEventURL != nil {
                    Button {
                        store.selectDraft(id: draft.id)
                        store.openSelectedCalendarEvent()
                    } label: {
                        Label("Open Calendar event", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DailyActionPanel: View {
    @ObservedObject var store: DemoHouseholdStore
    var draft: InboxDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Daily actions", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                if let triageState = draft.triageState, triageState != .active {
                    TriageBadge(state: triageState)
                }
                if let replyStatus = draft.replyStatus, replyStatus != ReplyWorkflowStatus.none {
                    ReplyStatusBadge(status: replyStatus)
                }
            }

            FlowButtonRow {
                Button {
                    store.openSelectedEmailInGmail()
                } label: {
                    Label("Open Email", systemImage: "envelope")
                }

                if draft.googleEventURL != nil {
                    Button {
                        store.openSelectedCalendarEvent()
                    } label: {
                        Label("Open Calendar", systemImage: "calendar")
                    }
                }

                Button {
                    store.markSelectedWaiting()
                } label: {
                    Label("Waiting", systemImage: "hourglass")
                }
                .disabled(draft.triageState == .waiting)

                Button {
                    store.markSelectedDone()
                } label: {
                    Label("Done", systemImage: "checkmark.circle")
                }
                .disabled(draft.triageState == .done)

                Button {
                    store.snoozeSelected(byDays: 1)
                } label: {
                    Label("Tomorrow", systemImage: "moon")
                }

                Button {
                    store.markSelectedNeedsReply()
                } label: {
                    Label("Needs Reply", systemImage: "arrowshape.turn.up.left")
                }
                .disabled(draft.replyStatus == .needsReply)

                Button {
                    store.markSelectedReplyDone()
                } label: {
                    Label("Reply Done", systemImage: "checkmark.message")
                }
                .disabled(draft.replyStatus == .done || draft.replyStatus == ReplyWorkflowStatus.none)

                Button {
                    store.markSelectedNotHousehold()
                } label: {
                    Label("Not Household", systemImage: "archivebox")
                }
                .disabled(draft.triageState == .notHousehold)

                Button(role: .destructive) {
                    store.ignoreSelectedSender()
                } label: {
                    Label("Ignore Sender", systemImage: "person.crop.circle.badge.xmark")
                }
            }

            if draft.status == .calendarRetryRequired || draft.status == .calendarUpdateRequired || draft.status == .changedExternally {
                Divider()

                FlowButtonRow {
                    if draft.status == .calendarRetryRequired {
                        Button {
                            Task { await store.retrySelectedCalendarWrite() }
                        } label: {
                            Label("Retry Calendar", systemImage: "arrow.clockwise.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if draft.status == .calendarUpdateRequired {
                        Button {
                            Task { await store.syncSelectedCalendarUpdate() }
                        } label: {
                            Label("Sync Calendar", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if draft.status == .changedExternally {
                        Button {
                            store.keepSelectedAppVersionForExternalChange()
                        } label: {
                            Label("Keep App Record", systemImage: "checkmark.seal")
                        }

                        Button {
                            store.acceptSelectedCalendarVersion()
                        } label: {
                            Label("Accept Calendar", systemImage: "calendar.badge.checkmark")
                        }

                        Button {
                            Task { await store.recreateSelectedCalendarEvent() }
                        } label: {
                            Label("Recreate Event", systemImage: "calendar.badge.plus")
                        }

                        Button {
                            store.markSelectedExternalChangeDone()
                        } label: {
                            Label("Mark Done", systemImage: "checkmark.circle")
                        }
                    }
                }

                if let lastError = draft.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FlowButtonRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                content()
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }
}

private struct EmailIntelligencePanel: View {
    @ObservedObject var store: DemoHouseholdStore
    var draft: InboxDraft
    var intelligence: EmailIntelligenceResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Email intelligence", systemImage: "sparkles")
                        .font(.headline)
                    Text(intelligence.summary)
                        .font(.callout.weight(.medium))
                    Text(intelligence.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                UrgencyBadge(urgency: intelligence.urgency)
            }

            HStack(spacing: 6) {
                ForEach(intelligence.tags, id: \.self) { tag in
                    Text(tag.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }

            if !intelligence.recommendedReminderMinutesBefore.isEmpty {
                Label(reminderText(intelligence.recommendedReminderMinutesBefore), systemImage: "bell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if shouldShowReplyComposer {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(replySectionTitle, systemImage: "arrowshape.turn.up.left")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let reply = intelligence.suggestedReply {
                            Text("\(Int(reply.confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(replySubject)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    TextEditor(text: Binding(
                        get: { store.replyDraft },
                        set: store.updateReplyDraft
                    ))
                    .font(.callout)
                    .frame(minHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    )

                    FlowButtonRow {
                        Button {
                            store.copySelectedReply()
                        } label: {
                            Label("Copy Reply", systemImage: "doc.on.doc")
                        }
                        Button {
                            Task { await store.saveSelectedReplyAsGmailDraft() }
                        } label: {
                            Label(
                                draft.gmailReplyDraftID == nil ? "Save Gmail Draft" : "Update Gmail Draft",
                                systemImage: "tray.and.arrow.down"
                            )
                        }
                        .disabled(!store.isGoogleConnected || store.isSavingGmailDraft)
                        .help("Creates or updates an unsent Gmail draft. It never sends the email.")
                        Button {
                            store.openSelectedReplyInGmailCompose()
                        } label: {
                            Label("Open Compose", systemImage: "square.and.pencil")
                        }
                        Button {
                            store.openSelectedEmailInGmail()
                        } label: {
                            Label("Find Email", systemImage: "magnifyingglass")
                        }
                        Button {
                            store.markSelectedReplySentManually()
                        } label: {
                            Label("Mark Sent", systemImage: "paperplane")
                        }
                        .disabled(draft.replyStatus == .sentManually || draft.replyStatus == .done)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var shouldShowReplyComposer: Bool {
        intelligence.suggestedReply != nil || draft.replyStatus?.requiresReplyAction == true
    }

    private var replySectionTitle: String {
        intelligence.suggestedReply == nil ? "Reply draft" : "Suggested reply"
    }

    private var replySubject: String {
        if let reply = intelligence.suggestedReply {
            return reply.subject
        }

        return GmailReplyComposer.replyDraft(for: draft, body: "").subject
    }
}

private struct ManualItemSheet: View {
    @ObservedObject var store: DemoHouseholdStore
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add household item")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                        Text("Capture it now. Decide whether it belongs on Calendar after review.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppPalette.muted)
                    }
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(MobileIconButtonStyle())
                }

                VStack(alignment: .leading, spacing: 12) {
                    TextField("What needs doing?", text: $store.newItemTitle)
                        .font(.system(size: 17, weight: .medium))
                        .textFieldStyle(.roundedBorder)

                    Toggle("Give it a due date", isOn: $store.newItemHasDueDate)
                        .toggleStyle(.switch)

                    if store.newItemHasDueDate {
                        DatePicker(
                            "Due",
                            selection: $store.newItemDueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    TextField("Amount (optional)", text: $store.newItemAmount)
                        .textFieldStyle(.roundedBorder)

                    Picker("Owner", selection: $store.newItemOwnerID) {
                        Text("Unassigned").tag("")
                        ForEach(store.household.members) { member in
                            Text(member.displayName).tag(member.id.uuidString)
                        }
                    }

                    Picker("Area", selection: $store.newItemAreaID) {
                        Text("No area").tag("")
                        ForEach(store.household.areas) { area in
                            Text(area.name).tag(area.id.uuidString)
                        }
                    }
                }
                .padding(14)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppPalette.line, lineWidth: 1)
                }

                Button {
                    store.createManualItem()
                    isPresented = false
                } label: {
                    Label("Add to inbox", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MobilePrimaryButtonStyle())
                .disabled(store.newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(minWidth: 360, idealWidth: 420, minHeight: 540)
        .background(AppPalette.canvas)
    }
}

private struct BillsView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "Bills And Obligations", subtitle: "Open finance-related household items due in the next seven days.")

                if store.dashboard.billsDueSoon.isEmpty {
                    ContentUnavailableView("No Bills Due Soon", systemImage: "creditcard", description: Text("Add an amount to any draft to track it as a bill or obligation."))
                } else {
                    ForEach(store.dashboard.billsDueSoon) { draft in
                        DraftSummaryCard(draft: draft, household: store.household, store: store)
                    }
                }
            }
            .padding(24)
        }
        .background(AppPalette.canvas)
    }
}

private struct RemindersView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "Calendar", subtitle: "Approve reminders, keep events in sync, and resolve changes made outside the app.")

                CalendarOverview(store: store)

                FlowButtonRow {
                    Button {
                        Task { await store.checkCalendarSync() }
                    } label: {
                        Label("Check for changes", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(MobilePrimaryButtonStyle())

                    Button {
                        store.openGoogleCalendar()
                    } label: {
                        Label("Open Calendar", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }

                Text("Last checked: \(store.lastCalendarSyncText)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted)

                if store.calendarReminderGroups.isEmpty {
                    MobileEmptyState(
                        title: "Nothing to schedule",
                        detail: "Add an item or discover Gmail emails. Items with due dates can be approved to Calendar here.",
                        systemImage: "calendar"
                    )
                } else {
                    ForEach(store.calendarReminderGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Label("\(group.state.label) \(group.drafts.count)", systemImage: icon(for: group.state))
                                .font(.headline)

                            ForEach(group.drafts) { draft in
                                ReminderCard(
                                    draft: draft,
                                    intelligence: store.intelligence(for: draft),
                                    readiness: store.calendarReadiness(for: draft),
                                    household: store.household,
                                    store: store
                                )
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(AppPalette.canvas)
    }

    private func icon(for state: CalendarReadinessState) -> String {
        switch state {
        case .needsDueDate:
            "calendar.badge.clock"
        case .readyToApprove:
            "calendar.badge.plus"
        case .scheduled:
            "calendar"
        case .retryRequired:
            "arrow.clockwise.circle"
        case .updateRequired:
            "arrow.triangle.2.circlepath"
        case .externalChange:
            "exclamationmark.arrow.triangle.2.circlepath"
        case .rejected:
            "xmark.circle"
        }
    }
}

private struct CalendarOverview: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        HStack(spacing: 10) {
            CalendarMetric(value: store.calendarActionCount, title: "need action", color: AppPalette.amberText, background: AppPalette.amberSoft)
            CalendarMetric(value: store.scheduledCalendarCount, title: "on Calendar", color: AppPalette.teal, background: AppPalette.teal.opacity(0.13))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.isGoogleConnected ? "Google Calendar connected" : "Calendar demo mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                Text(store.isGoogleConnected ? store.googleCalendarID : "Connect Google in Household settings")
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppPalette.line, lineWidth: 1)
        }
    }
}

private struct CalendarMetric: View {
    var value: Int
    var title: String
    var color: Color
    var background: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .frame(width: 76, height: 56)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct WeeklyReviewView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Weekly Review", subtitle: "Unassigned work, failed Calendar writes, and Calendar items changed outside the app.")
                        Text("Last Calendar sync: \(store.lastCalendarSyncText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await store.checkCalendarSync() }
                    } label: {
                        Label("Check Calendar", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                if store.dashboard.weeklyReviewItems.isEmpty {
                    ContentUnavailableView("Review Queue Clear", systemImage: "checkmark.circle", description: Text("No unassigned, retry, or externally changed items need attention."))
                } else {
                    ForEach(store.dashboard.weeklyReviewItems) { draft in
                        DraftSummaryCard(draft: draft, household: store.household, store: store)
                    }
                }
            }
            .padding(24)
        }
        .background(AppPalette.canvas)
    }
}

private struct BankingView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "Banking Candidates", subtitle: "Bills and payment emails that can later be matched against bunq transactions.")

                SettingsGroup(title: "bunq Private Test", icon: "building.columns") {
                    Text("Planned as read-only matching first: find expected payments from Gmail, then reconcile against bank transactions.")
                    Text("No payment initiation, no transaction ledger, and no budget model in this app until the household workflow is solid.")
                        .foregroundStyle(.secondary)
                    Button {
                        store.syncMessage = "bunq is not connected yet. Next build should add sandbox OAuth and read-only transaction matching."
                    } label: {
                        Label("Prepare bunq Sandbox", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.bordered)
                }

                if store.bankingCandidateDrafts.isEmpty {
                    ContentUnavailableView("No Banking Matches Yet", systemImage: "building.columns", description: Text("Emails with amounts, invoices, payments, renewals, or subscriptions will appear here."))
                } else {
                    ForEach(store.bankingCandidateDrafts) { draft in
                        BankingCandidateCard(draft: draft, intelligence: store.intelligence(for: draft), household: store.household, store: store)
                    }
                }
            }
            .padding(24)
        }
        .background(AppPalette.canvas)
    }
}

private struct AreasView: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "Household", subtitle: "Default owners, workload, settings, and review tools.")

                FlowButtonRow {
                    Button {
                        store.selectedSection = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button {
                        store.selectedSection = .review
                    } label: {
                        Label("Review", systemImage: "checklist")
                    }
                    Button {
                        store.selectedSection = .banking
                    } label: {
                        Label("Banking", systemImage: "building.columns")
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(store.dashboard.areaSummaries) { summary in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(summary.areaName)
                                    .font(.headline)
                                Spacer()
                                Text("\(summary.activeItemCount)")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                            }
                            Text(summary.defaultOwnerName ?? "No default owner")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Label(summary.openObligationTotal.description, systemImage: "creditcard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(24)
        }
        .background(AppPalette.canvas)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: DemoHouseholdStore

    private var scopes: [GoogleOAuthScope] {
        [.gmailReadonly, .gmailCompose, .calendarEvents, .openid, .email, .profile]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeader(title: "Integration Settings", subtitle: "Google connects Gmail discovery, unsent reply drafts, and real Calendar approval.")

                SettingsGroup(title: "Google OAuth", icon: "person.badge.key") {
                    Text("Desktop Client ID")
                        .font(.caption.weight(.semibold))
                    TextField("4229...apps.googleusercontent.com", text: $store.googleClientID)
                        .font(.callout.monospaced())
                        .textFieldStyle(.roundedBorder)

                    Text("Desktop Client Secret")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 8)
                    SecureField("GOCSPX-...", text: $store.googleClientSecret)
                        .font(.callout.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .help("Stored in Keychain after a successful connection. Required by this Google Desktop OAuth client.")

                    Text("Test account")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 8)
                    TextField("house.marcansu@gmail.com", text: $store.googleExpectedAccount)
                        .textFieldStyle(.roundedBorder)

                    Text("Calendar ID")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 8)
                    TextField("primary", text: $store.googleCalendarID)
                        .font(.callout.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .help("Use primary for the signed-in account, or paste a shared Google Calendar ID.")

                    Text("Status")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 8)
                    Text(store.googleConnectionStatus)
                        .foregroundStyle(store.isGoogleConnected ? .green : .secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Reconnect Google once to grant Gmail draft access. The app creates or updates drafts only; it never sends email automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !store.lastGoogleError.isEmpty {
                        Text("Last Google error")
                            .font(.caption.weight(.semibold))
                            .padding(.top, 8)
                        Text(store.lastGoogleError)
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    }

                    HStack {
                        Button {
                            Task { await store.connectGoogle() }
                        } label: {
                            Label(store.isGoogleConnected ? "Reconnect Google" : "Connect Google", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isConnectingGoogle || store.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            store.disconnectGoogle()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                        .disabled(!store.isGoogleConnected)
                    }

                    Button {
                        Task { await store.importGmailLabel() }
                    } label: {
                        Label("Discover Gmail Emails", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(store.isConnectingGoogle)

                    Text("Redirect URI")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 8)
                    Text("http://127.0.0.1:<random-port>")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text("Scopes")
                        .font(.caption.weight(.semibold))
                        .padding(.top, 8)
                    ForEach(scopes, id: \.rawValue) { scope in
                        Text(scope.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsGroup(title: "Backend Later", icon: "externaldrive.connected.to.line.below") {
                    Text("The app is local-first while the product shape is still changing.")
                    Text("A database can later sync households, members, approval events, ignored senders, and Google object mappings without changing the daily workflow.")
                        .foregroundStyle(.secondary)
                }

                SettingsGroup(title: "Local Demo Mode", icon: "shippingbox") {
                    Text("When Google is disconnected, Gmail import and Calendar approval use local demo adapters.")
                    Text("Email intelligence runs locally with deterministic rules. Backend AI extraction can replace it later without changing the inbox workflow.")
                        .foregroundStyle(.secondary)
                }

                SettingsGroup(title: "Local Storage", icon: "internaldrive") {
                    Text("Drafts, edits, approvals, Calendar mappings, ignored senders, and reply text are stored locally until the product is ready for a real database.")
                    Text("Last Calendar sync: \(store.lastCalendarSyncText)")
                        .foregroundStyle(.secondary)
                    Text("Ignored senders: \(store.ignoredSenderCount)")
                        .foregroundStyle(.secondary)
                    Text(store.localStoragePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsGroup(title: "Banking", icon: "building.columns") {
                    Text("The app now marks banking candidates from emails with amounts, invoices, renewals, and payment language.")
                    Text("bunq should be added as a read-only sandbox connector first, then matched against these candidates. No payments should be initiated from v1.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .background(AppPalette.canvas)
        .onAppear {
            store.refreshGoogleConnectionStatus()
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DraftSummaryCard: View {
    var draft: InboxDraft
    var household: HouseholdContext
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        Button {
            store.selectDraft(id: draft.id)
            store.selectedSection = .inbox
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(draft.title)
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: draft.status)
                }
                InboxRow(draft: draft, household: household, intelligence: store.intelligence(for: draft))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct ReminderCard: View {
    var draft: InboxDraft
    var intelligence: EmailIntelligenceResult
    var readiness: CalendarReadiness
    var household: HouseholdContext
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(draft.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                CalendarReadinessBadge(state: readiness.state)
            }

            Text(readiness.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                UrgencyBadge(urgency: intelligence.urgency)
                if let dueDate = draft.dueDate {
                    Label(shortDate(dueDate), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !readiness.recommendedReminderMinutesBefore.isEmpty {
                    Label(reminderText(readiness.recommendedReminderMinutesBefore), systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            FlowButtonRow {
                Button {
                    store.selectDraft(id: draft.id)
                    store.selectedSection = .inbox
                } label: {
                    Label("Review", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                if draft.googleEventURL != nil {
                    Button {
                        store.selectDraft(id: draft.id)
                        store.openSelectedCalendarEvent()
                    } label: {
                        Label("Open event", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }

                if readiness.canApproveToCalendar {
                    Button(action: performCalendarAction) {
                        Label(calendarActionTitle, systemImage: calendarActionIcon)
                    }
                    .buttonStyle(MobilePrimaryButtonStyle())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppPalette.line, lineWidth: 1)
        }
    }

    private var calendarActionTitle: String {
        switch draft.status {
        case .calendarRetryRequired:
            "Retry"
        case .calendarUpdateRequired:
            "Sync"
        default:
            "Approve"
        }
    }

    private var calendarActionIcon: String {
        switch draft.status {
        case .calendarRetryRequired:
            "arrow.clockwise"
        case .calendarUpdateRequired:
            "arrow.triangle.2.circlepath"
        default:
            "calendar.badge.plus"
        }
    }

    private func performCalendarAction() {
        store.selectDraft(id: draft.id)
        switch draft.status {
        case .calendarRetryRequired:
            Task { await store.retrySelectedCalendarWrite() }
        case .calendarUpdateRequired:
            Task { await store.syncSelectedCalendarUpdate() }
        default:
            Task { await store.approveSelectedDraft() }
        }
    }
}

private struct BankingCandidateCard: View {
    var draft: InboxDraft
    var intelligence: EmailIntelligenceResult
    var household: HouseholdContext
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        Button {
            store.selectDraft(id: draft.id)
            store.selectedSection = .inbox
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(draft.title, systemImage: "creditcard")
                        .font(.headline)
                    Spacer()
                    if let amount = draft.amount {
                        Text(amount.description)
                            .font(.system(.headline, design: .rounded))
                    }
                }
                Text(intelligence.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                InboxRow(draft: draft, household: household, intelligence: intelligence)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct SectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(AppPalette.muted)
        }
    }
}

private struct SourceEvidenceView: View {
    var draft: InboxDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI extraction", systemImage: "wand.and.stars")
                .font(.headline)
            Text("Confidence \(draft.extractionConfidence.formatted(.number.precision(.fractionLength(2))))")
                .foregroundStyle(confidenceColor)

            if !draft.evidence.isEmpty {
                ForEach(draft.evidence, id: \.self) { evidence in
                    Text(evidence)
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Text(draft.source.bodyPreview)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var confidenceColor: Color {
        draft.extractionConfidence >= DraftFactory.minimumActionConfidence ? .secondary : .orange
    }
}

private struct ConnectionsPanel: View {
    @ObservedObject var store: DemoHouseholdStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connections")
                .font(.headline)

            ConnectionRow(
                icon: "envelope",
                title: "Gmail",
                detail: store.isGoogleConnected ? "\(store.googleExpectedAccount), auto-discovery" : "Demo mode",
                state: store.isGoogleConnected ? "Live" : "Demo"
            )
            ConnectionRow(
                icon: "calendar",
                title: "Google Calendar",
                detail: store.isGoogleConnected ? store.googleCalendarID : (store.household.sharedCalendarID ?? "Demo calendar"),
                state: store.isGoogleConnected ? "Live" : "Demo"
            )
            ConnectionRow(icon: "internaldrive", title: "Local Storage", detail: "Drafts, decisions, replies, and mappings", state: "Live")
            ConnectionRow(icon: "sparkles", title: "Email intelligence", detail: "Urgency, tags, replies, reminders", state: "Local")
            ConnectionRow(icon: "building.columns", title: "Banking", detail: "bunq candidate matching next", state: "Staged")

            Divider()

            Text("Calendar is canonical. Gmail discovery feeds drafts. Banking stays read-only matching until the household workflow proves useful.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ConnectionRow: View {
    var icon: String
    var title: String
    var detail: String
    var state: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(state)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MetricPill: View {
    var title: String
    var value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 72)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusBadge: View {
    var status: InboxDraftStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch status {
        case .pendingApproval:
            "Pending"
        case .approved:
            "Approved"
        case .rejected:
            "Rejected"
        case .calendarRetryRequired:
            "Retry"
        case .calendarUpdateRequired:
            "Needs Sync"
        case .changedExternally:
            "External"
        }
    }

    private var color: Color {
        switch status {
        case .pendingApproval:
            .blue
        case .approved:
            .green
        case .rejected:
            .red
        case .calendarRetryRequired:
            .orange
        case .calendarUpdateRequired:
            .orange
        case .changedExternally:
            .purple
        }
    }
}

private struct TriageBadge: View {
    var state: DraftTriageState

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch state {
        case .active:
            "Active"
        case .waiting:
            "Waiting"
        case .done:
            "Done"
        case .notHousehold:
            "Not Household"
        }
    }

    private var color: Color {
        switch state {
        case .active:
            .blue
        case .waiting:
            .orange
        case .done:
            .green
        case .notHousehold:
            .secondary
        }
    }
}

private struct ReplyStatusBadge: View {
    var status: ReplyWorkflowStatus

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch status {
        case .none:
            "No Reply"
        case .needsReply:
            "Needs Reply"
        case .drafted:
            "Reply Drafted"
        case .copied:
            "Reply Copied"
        case .openedInGmail:
            "Opened Gmail"
        case .savedToGmailDraft:
            "Gmail Draft"
        case .sentManually:
            "Sent"
        case .done:
            "Reply Done"
        }
    }

    private var color: Color {
        switch status {
        case .none:
            .secondary
        case .needsReply:
            .blue
        case .drafted:
            .blue
        case .copied:
            .purple
        case .openedInGmail:
            .orange
        case .savedToGmailDraft:
            .purple
        case .sentManually:
            .green
        case .done:
            .green
        }
    }
}

private struct UrgencyBadge: View {
    var urgency: EmailUrgency

    var body: some View {
        Text(urgency.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch urgency {
        case .immediate:
            .red
        case .soon:
            .orange
        case .normal:
            .blue
        case .low:
            .secondary
        }
    }
}

private struct CalendarReadinessBadge: View {
    var state: CalendarReadinessState

    var body: some View {
        Text(state.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch state {
        case .needsDueDate:
            .orange
        case .readyToApprove:
            .blue
        case .scheduled:
            .green
        case .retryRequired:
            .orange
        case .updateRequired:
            .orange
        case .externalChange:
            .purple
        case .rejected:
            .red
        }
    }
}

private func shortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func reminderText(_ minutes: [Int]) -> String {
    guard !minutes.isEmpty else {
        return "No reminder suggested until a due date is set"
    }

    let labels = minutes.map { minute in
        if minute % 1_440 == 0 {
            let days = minute / 1_440
            return "\(days)d"
        }
        if minute % 60 == 0 {
            return "\(minute / 60)h"
        }
        return "\(minute)m"
    }

    return "Suggested reminders: \(labels.joined(separator: ", ")) before due"
}
