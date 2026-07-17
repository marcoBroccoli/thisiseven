import XCTest
@testable import HouseholdCore

final class EmailIntelligenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAnalyzerMarksOverdueBillAsUrgentWithReplyAndBankingTags() {
        let household = makeHousehold()
        let draft = makeDraft(
            title: "Final notice: electricity payment overdue",
            dueDate: now,
            amount: Decimal(string: "84.25"),
            bodyPreview: "Please pay EUR 84.25 by today and reply once payment is complete."
        )
        let analyzer = EmailIntelligenceAnalyzer()

        let result = analyzer.analyze(draft: draft, household: household, now: now)

        XCTAssertEqual(result.urgency, .immediate)
        XCTAssertTrue(result.tags.contains(.bill))
        XCTAssertTrue(result.tags.contains(.replyNeeded))
        XCTAssertTrue(result.tags.contains(.bankingCandidate))
        XCTAssertEqual(result.primaryAction, .payAndReply)
        XCTAssertEqual(result.recommendedReminderMinutesBefore, [60, 15])
        XCTAssertEqual(result.suggestedReply?.subject, "Re: Final notice: electricity payment overdue")
        XCTAssertTrue(result.suggestedReply?.body.contains("I’ll take care of this") == true)
    }

    func testAnalyzerMarksAppointmentAsCalendarWorkWithConfirmationReply() {
        let household = makeHousehold()
        let dueDate = now.addingTimeInterval(3 * 86_400)
        let draft = makeDraft(
            title: "Dentist appointment confirmation",
            dueDate: dueDate,
            amount: nil,
            bodyPreview: "Can you confirm this dentist appointment for Monday?"
        )
        let analyzer = EmailIntelligenceAnalyzer()

        let result = analyzer.analyze(draft: draft, household: household, now: now)

        XCTAssertEqual(result.urgency, .normal)
        XCTAssertTrue(result.tags.contains(.appointment))
        XCTAssertTrue(result.tags.contains(.calendar))
        XCTAssertTrue(result.tags.contains(.replyNeeded))
        XCTAssertEqual(result.primaryAction, .scheduleAndReply)
        XCTAssertEqual(result.recommendedReminderMinutesBefore, [2880, 1440])
        XCTAssertTrue(result.suggestedReply?.body.contains("confirm") == true)
    }

    func testInboxPresentationGroupsDraftsByActionableTriageWithoutDuplicates() {
        let household = makeHousehold()
        let urgent = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            title: "Bill due today",
            dueDate: now,
            amount: Decimal(45),
            bodyPreview: "Invoice due today."
        )
        let reply = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            title: "Can you confirm school form?",
            dueDate: now.addingTimeInterval(4 * 86_400),
            amount: nil,
            bodyPreview: "Please reply to confirm the form is complete."
        )
        let later = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            title: "Subscription renewal next month",
            dueDate: now.addingTimeInterval(30 * 86_400),
            amount: Decimal(9.99),
            bodyPreview: "Your plan renews next month."
        )
        let model = InboxPresentationModel(drafts: [later, reply, urgent])

        let buckets = model.triageBuckets(household: household, now: now)

        XCTAssertEqual(buckets.map(\.title), ["Urgent", "Needs Reply", "Bills"])
        XCTAssertEqual(buckets.flatMap(\.drafts).map(\.id), [urgent.id, reply.id, later.id])
    }

    func testCalendarRetryDraftIsGroupedForCalendarSyncReview() {
        let household = makeHousehold()
        var draft = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            title: "Calendar write failed",
            dueDate: now.addingTimeInterval(86_400),
            amount: nil,
            bodyPreview: "Needs calendar retry."
        )
        draft.status = .calendarRetryRequired
        let model = InboxPresentationModel(drafts: [draft])

        let buckets = model.triageBuckets(household: household, now: now)

        XCTAssertEqual(buckets.map(\.title), ["Calendar Sync"])
        XCTAssertEqual(buckets[0].drafts.map(\.id), [draft.id])
    }

    private func makeHousehold() -> HouseholdContext {
        let member = HouseholdMember(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            displayName: "Marco",
            email: "marco@example.com"
        )
        let utilities = HouseholdArea(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            name: "Utilities",
            defaultOwnerID: member.id
        )
        let admin = HouseholdArea(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            name: "Admin",
            defaultOwnerID: member.id
        )
        return HouseholdContext(id: UUID(), members: [member], areas: [utilities, admin], sharedCalendarID: "primary")
    }

    private func makeDraft(
        id: UUID = UUID(),
        title: String,
        dueDate: Date?,
        amount: Decimal?,
        bodyPreview: String
    ) -> InboxDraft {
        InboxDraft.pending(
            id: id,
            source: SourceEmail(
                gmailMessageID: "msg-\(id.uuidString)",
                subject: title,
                from: "sender@example.com",
                receivedAt: now,
                label: "Auto Household",
                bodyPreview: bodyPreview
            ),
            title: title,
            dueDate: dueDate,
            amount: amount,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: [bodyPreview]
        )
    }
}
