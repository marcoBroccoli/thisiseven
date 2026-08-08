import Foundation

/// Central domain fixtures for SwiftUI previews and Feature `PreviewSupport`.
/// Features / Design / app shell reference these — do not invent inline mocks.
public enum PreviewData {
    public static let adaId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    public static let umutId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    public static let householdId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    public static let weekId = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!

    public static let ada = Member(
        id: adaId, displayName: "Ada", color: .clay, isMe: true
    )
    public static let umut = Member(
        id: umutId, displayName: "Umut", color: .teal, isMe: false
    )

    public static let household = Household(
        id: householdId,
        name: "The Attic",
        inviteCode: "EVEN-7K2M",
        members: [ada, umut]
    )

    public static let week = Week(
        id: weekId, index: 12, startedOn: "2026-08-03", closedAt: nil
    )

    public static let me = MeResponse(
        userId: adaId, member: ada, household: household, week: week
    )

    public static func task(
        id: UUID = UUID(),
        title: String,
        section: TaskSection = .chore,
        owner: UUID = adaId,
        weight: Int = 2,
        recurrence: Recurrence = .none,
        dueOn: String? = "2026-08-05",
        done: Bool = false,
        meta: String = "TODAY · ONE-OFF"
    ) -> HouseholdTask {
        HouseholdTask(
            id: id,
            title: title,
            section: section,
            ownerMemberId: owner,
            weight: weight,
            recurrence: recurrence,
            dueOn: dueOn,
            done: done,
            doneByMemberId: done ? owner : nil,
            metaLine: meta,
            googleEventUrl: nil,
            calendarSyncState: .synced,
            calendarLastSyncedAt: nil,
            calendarLastError: nil
        )
    }

    public static let laundry = task(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        title: "Laundry — towels & bedding",
        weight: 2,
        recurrence: .weekly,
        dueOn: "2026-08-07",
        meta: "TODAY · WEEKLY"
    )

    public static let dishes = task(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        title: "Dishes tonight",
        owner: umutId,
        weight: 1,
        recurrence: .daily,
        dueOn: "2026-08-08",
        meta: "TOMORROW · DAILY"
    )

    public static let waterBill = task(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        title: "Pay Waternet water bill — Q2",
        section: .admin,
        owner: umutId,
        weight: 2,
        dueOn: "2026-08-05",
        meta: "GMAIL · €84.30 · 2 DAYS OVER"
    )

    /// Done this week — Ada weight 2 (pebble).
    public static let trash = task(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        title: "Take out the trash",
        weight: 2,
        recurrence: .weekly,
        dueOn: "2026-08-07",
        done: true,
        meta: "DONE · WEEKLY"
    )

    /// Done this week — Ada weight 3 (pebble).
    public static let groceries = task(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        title: "Weekly groceries run",
        weight: 3,
        dueOn: nil,
        done: true,
        meta: "DONE"
    )

    /// Done this week — Umut weight 1 (pebble).
    public static let vacuum = task(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        title: "Vacuum the hallway",
        owner: umutId,
        weight: 1,
        dueOn: "2026-08-12",
        done: true,
        meta: "DONE"
    )

    /// Done this week — Umut weight 3 (pebble).
    public static let insurance = task(
        id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
        title: "File insurance claim — bike",
        section: .admin,
        owner: umutId,
        weight: 3,
        dueOn: "2026-08-04",
        done: true,
        meta: "DONE · GMAIL"
    )

    public static let summaryEmpty = Summary(
        week: week,
        // Nothing done on either side → no pebbles. Weight-0 placeholders are
        // not the same as none: the beam draws a ball for every entry.
        pebbles: [],
        percentMe: 50,
        percentPartner: 50,
        caption: "Nothing on the beam yet.",
        sections: [],
        pendingDraftCount: 0
    )

    /// Open work + completed chores that seed the beam pebbles (Ada 2+3, Umut 1+3 → 57/43).
    public static let summary = Summary(
        week: week,
        pebbles: [
            Pebble(memberId: adaId, weight: trash.weight),
            Pebble(memberId: adaId, weight: groceries.weight),
            Pebble(memberId: umutId, weight: vacuum.weight),
            Pebble(memberId: umutId, weight: insurance.weight),
        ],
        percentMe: 57,
        percentPartner: 43,
        caption: "Leaning Ada — mostly the admin and the remembering",
        sections: [
            SummarySection(
                key: .chore,
                label: "CHORES",
                tasks: [laundry, dishes, trash, groceries, vacuum]
            ),
            SummarySection(
                key: .admin,
                label: "ADMIN",
                tasks: [waterBill, insurance]
            ),
        ],
        pendingDraftCount: 2
    )

    public static func draft(
        id: UUID = UUID(),
        from: String,
        subject: String,
        summary: String? = nil,
        title: String? = nil,
        amountCents: Int? = nil
    ) -> Draft {
        Draft(
            id: id,
            fromLabel: from,
            subject: subject,
            summary: summary,
            urgency: 2,
            title: title ?? subject,
            ownerMemberId: adaId,
            amountCents: amountCents,
            dueOn: "2026-08-08",
            reminder: .threeDays,
            status: .pending,
            createdByMemberId: adaId,
            sourceFrom: from,
            sourcePreview: summary,
            gmail: true,
            gmailMessageId: "msg-preview",
            category: "bill",
            needsReply: false,
            suggestedReply: nil,
            replyText: nil,
            replyStatus: DraftReplyStatus.none
        )
    }

    public static let pendingDrafts: [Draft] = [
        draft(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            from: "City of Utrecht",
            subject: "Water bill — €84, due Friday",
            summary: "€84.30 · due soon",
            amountCents: 8430
        ),
        draft(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            from: "Zilveren Kruis",
            subject: "Decide health-insurance renewal",
            summary: "Due today"
        ),
    ]

    public static let googleConnected = GoogleStatus(
        connected: true,
        partnerConnected: false,
        email: "ada@example.com",
        lastSyncAt: Date(timeIntervalSince1970: 1_720_000_000),
        lastSyncCount: 6,
        calendarLastSyncAt: nil,
        syncRunning: false,
        scanned: 6,
        classified: 4,
        created: 2,
        hasMore: false
    )

    /// A scan in flight — the inbox's fetch control follows these counters.
    public static let googleSyncing = GoogleStatus(
        connected: true,
        partnerConnected: false,
        email: "ada@example.com",
        lastSyncAt: Date(timeIntervalSince1970: 1_720_000_000),
        lastSyncCount: 6,
        calendarLastSyncAt: nil,
        syncRunning: true,
        scanned: 12,
        classified: 10,
        created: 3,
        hasMore: true
    )

    public static let googleDisconnected = GoogleStatus(
        connected: false,
        partnerConnected: false,
        email: nil,
        lastSyncAt: nil,
        lastSyncCount: nil,
        calendarLastSyncAt: nil,
        syncRunning: nil,
        scanned: nil,
        classified: nil,
        created: nil,
        hasMore: nil
    )

    /// The joined partner's view before they connect anything of their own:
    /// not connected, but the household's calendar is already live.
    public static let googlePartnerConnectedOnly = GoogleStatus(
        connected: false,
        partnerConnected: true,
        email: nil,
        lastSyncAt: nil,
        lastSyncCount: nil,
        calendarLastSyncAt: Date(timeIntervalSince1970: 1_720_000_000),
        syncRunning: nil,
        scanned: nil,
        classified: nil,
        created: nil,
        hasMore: nil
    )

    /// The partner's view before they confirm: a shared calendar exists on the
    /// other account, and the one-tap add applies to them.
    public static let calendarInfoCanAdd = GoogleCalendarInfo(
        calendarId: "even-household-cal",
        shared: true,
        shareUrl: "https://calendar.google.com/calendar/r?cid=ZXZlbg",
        owner: false,
        listed: false,
        canAdd: true
    )

    /// After the confirm — or for the member whose account owns it.
    public static let calendarInfoListed = GoogleCalendarInfo(
        calendarId: "even-household-cal",
        shared: true,
        shareUrl: "https://calendar.google.com/calendar/r?cid=ZXZlbg",
        owner: false,
        listed: true,
        canAdd: false
    )

    public static let calendarInfoOwner = GoogleCalendarInfo(
        calendarId: "even-household-cal",
        shared: true,
        shareUrl: "https://calendar.google.com/calendar/r?cid=ZXZlbg",
        owner: true,
        listed: true,
        canAdd: false
    )

    /// No dated todo has been approved yet, so no calendar exists to add.
    public static let calendarInfoNotReady = GoogleCalendarInfo(
        calendarId: "primary",
        shared: false,
        owner: false,
        listed: false,
        canAdd: false
    )

    public static let calendarAdded = GoogleCalendarAddResult(
        calendarId: "even-household-cal", listed: true, owner: false
    )

    public static let widgetSnapshot = EvenWidgetSnapshot.placeholder

    public static let calendarSync = CalendarSyncResult(
        calendarId: "preview-household-cal",
        imported: 0,
        updated: 0,
        deleted: 0,
        unchanged: 2,
        lastSyncedAt: Date(timeIntervalSince1970: 1_720_000_000)
    )

    public static let calendarMonth = CalendarResponse(
        from: "2026-08-01",
        to: "2026-08-31",
        items: [
            CalendarItem(
                kind: .task,
                id: "task-\(waterBill.id.uuidString.lowercased())",
                title: waterBill.title,
                category: "bill",
                ownerMemberId: umutId,
                amountCents: 8430,
                dueOn: "2026-08-08",
                done: false,
                googleEventUrl: "https://calendar.google.com"
            ),
            CalendarItem(
                kind: .draft,
                id: "draft-\(pendingDrafts[0].id.uuidString.lowercased())",
                title: pendingDrafts[0].title,
                category: "bill",
                ownerMemberId: adaId,
                amountCents: 8430,
                dueOn: "2026-08-08",
                done: nil,
                googleEventUrl: nil
            ),
        ]
    )

    // MARK: - The Sunday reset ("the pour")

    public static let appreciationId = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
    public static let tradeId = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

    /// Umut has written his; Ada has not — the partner's stays veiled until she does.
    public static let appreciationFromPartner = Appreciation(
        id: appreciationId,
        fromMemberId: umutId,
        toMemberId: adaId,
        body: "You kept the whole week upright while I was away. I noticed.",
        said: false
    )

    public static let appreciationFromMe = Appreciation(
        id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEF")!,
        fromMemberId: adaId,
        toMemberId: umutId,
        body: "Thank you for the insurance call. That one was dread, not work.",
        said: true
    )

    public static let pendingTrade = Trade(
        id: tradeId,
        taskId: vacuum.id,
        taskTitle: vacuum.title,
        fromMemberId: adaId,
        toMemberId: umutId,
        accepted: false
    )

    /// Rows mirror `summary` (Ada 57 / Umut 43 overall).
    public static let resetRows = [
        ResetRow(key: "chores", label: "Chores", mePct: 62, partnerPct: 38),
        ResetRow(key: "admin", label: "The admin", mePct: 40, partnerPct: 60),
        ResetRow(key: "money", label: "Money fronted", mePct: 71, partnerPct: 29),
    ]

    public static let resetSummary = ResetSummary(
        week: week,
        rows: resetRows,
        biggestCarry: "Ada did the heavy lifting on chores — 62% by weight.",
        appreciations: [appreciationFromPartner],
        trades: [pendingTrade]
    )

    /// No partner yet — the appreciation exchange has nobody to exchange with.
    public static let resetSummarySolo = ResetSummary(
        week: week,
        rows: [
            ResetRow(key: "chores", label: "Chores", mePct: 100, partnerPct: 0),
            ResetRow(key: "admin", label: "The admin", mePct: 100, partnerPct: 0),
            ResetRow(key: "money", label: "Money fronted", mePct: 100, partnerPct: 0),
        ],
        biggestCarry: "A quiet week. Nothing carried, nothing owed.",
        appreciations: [],
        trades: []
    )

    public static let weekClose = WeekCloseResponse(
        closedWeek: Week(
            id: weekId, index: week.index, startedOn: week.startedOn,
            closedAt: Date(timeIntervalSince1970: 1_754_600_000)
        ),
        newWeek: Week(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDE")!,
            index: week.index + 1,
            startedOn: "2026-08-10",
            closedAt: nil
        )
    )
}
