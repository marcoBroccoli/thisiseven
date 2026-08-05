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
        meta: "TODAY · WEEKLY"
    )

    public static let dishes = task(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        title: "Dishes tonight",
        owner: umutId,
        weight: 1,
        recurrence: .daily,
        meta: "TODAY · DAILY"
    )

    public static let waterBill = task(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        title: "Pay Waternet water bill — Q2",
        section: .admin,
        owner: umutId,
        weight: 2,
        meta: "GMAIL · €84.30 · 2 DAYS OVER"
    )

    public static let summaryEmpty = Summary(
        week: week,
        pebbles: [
            Pebble(memberId: adaId, weight: 0),
            Pebble(memberId: umutId, weight: 0),
        ],
        percentMe: 50,
        percentPartner: 50,
        caption: "Nothing on the beam yet.",
        sections: [],
        pendingDraftCount: 0
    )

    public static let summary = Summary(
        week: week,
        pebbles: [
            Pebble(memberId: adaId, weight: 5),
            Pebble(memberId: umutId, weight: 4),
        ],
        percentMe: 57,
        percentPartner: 43,
        caption: "Leaning Ada — mostly the admin and the remembering.",
        sections: [
            SummarySection(key: .chore, label: "CHORES", tasks: [laundry, dishes]),
            SummarySection(key: .admin, label: "ADMIN", tasks: [waterBill]),
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

    public static let googleDisconnected = GoogleStatus(
        connected: false,
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

    public static let widgetSnapshot = EvenWidgetSnapshot.placeholder

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
}
