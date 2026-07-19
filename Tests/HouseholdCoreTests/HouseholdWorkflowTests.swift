import XCTest
@testable import HouseholdCore

final class HouseholdWorkflowTests: XCTestCase {
    func testDraftUsesAreaDefaultOwnerWhenExtractionHasAreaButNoOwner() {
        let member = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Marco", email: "marco@example.com")
        let area = HouseholdArea(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, name: "Utilities", defaultOwnerID: member.id)
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [member],
            areas: [area],
            sharedCalendarID: "calendar@example.com"
        )
        let email = SourceEmail(
            gmailMessageID: "msg-1",
            subject: "Energy bill due",
            from: "utility@example.com",
            receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
            label: "HouseholdTodo",
            bodyPreview: "Please pay before Friday."
        )
        let extraction = ExtractionResult(
            title: "Pay energy bill",
            dueDate: Date(timeIntervalSince1970: 1_800_086_400),
            amount: Decimal(84.15),
            suggestedOwnerID: nil,
            areaID: area.id,
            evidence: ["Please pay before Friday."],
            confidence: 0.82
        )

        let draft = DraftFactory.makeDraft(from: email, extraction: extraction, household: household)

        XCTAssertEqual(draft.ownerID, member.id)
        XCTAssertEqual(draft.areaID, area.id)
        XCTAssertEqual(draft.status, .pendingApproval)
    }

    func testApprovalCreatesCalendarEventAndStoresMapping() async throws {
        let owner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Marco", email: "marco@example.com")
        let partner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, displayName: "Partner", email: "partner@example.com")
        let area = HouseholdArea(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, name: "Subscriptions", defaultOwnerID: owner.id)
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [owner, partner],
            areas: [area],
            sharedCalendarID: "household@example.com"
        )
        let dueDate = Date(timeIntervalSince1970: 1_800_172_800)
        var draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-renewal",
                subject: "Insurance renewal",
                from: "insurance@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "Renew by Monday."
            ),
            title: "Renew insurance",
            dueDate: dueDate,
            amount: Decimal(129.99),
            ownerID: owner.id,
            areaID: area.id,
            extractionConfidence: 0.91,
            evidence: ["Renew by Monday."]
        )
        draft.approverID = partner.id
        let calendar = RecordingCalendarClient(result: .success(CalendarEventReference(id: "event-123", url: URL(string: "https://calendar.google.com/event?eid=123")!)))
        let service = HouseholdApprovalService(calendar: calendar, appBaseURL: URL(string: "household://drafts")!)

        let approved = await service.approve(draft, in: household)

        XCTAssertEqual(approved.status, .approved)
        XCTAssertEqual(approved.googleEventID, "event-123")
        XCTAssertEqual(calendar.createdEvents.count, 1)
        XCTAssertEqual(calendar.createdEvents[0].calendarID, "household@example.com")
        XCTAssertEqual(calendar.createdEvents[0].title, "Renew insurance")
        XCTAssertEqual(calendar.createdEvents[0].dueDate, dueDate)
        XCTAssertEqual(calendar.createdEvents[0].attendeeEmails, ["marco@example.com", "partner@example.com"])
        XCTAssertTrue(calendar.createdEvents[0].notes.contains("Source: Insurance renewal"))
    }

    func testApprovalUsesSuppliedReminderMinutes() async throws {
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [],
            areas: [],
            sharedCalendarID: "household@example.com"
        )
        let draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-urgent",
                subject: "Urgent payment",
                from: "sender@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "Due today."
            ),
            title: "Pay today",
            dueDate: Date(timeIntervalSince1970: 1_800_086_400),
            amount: Decimal(20),
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: []
        )
        let calendar = RecordingCalendarClient(result: .success(CalendarEventReference(id: "event-urgent", url: nil)))
        let service = HouseholdApprovalService(calendar: calendar, appBaseURL: URL(string: "household://drafts")!)

        _ = await service.approve(draft, in: household, reminderMinutesBefore: [60, 15])

        XCTAssertEqual(calendar.createdEvents[0].reminderMinutesBefore, [60, 15])
    }

    func testApprovalCarriesNoCostRecurrenceToCalendar() async {
        let household = HouseholdContext(
            id: UUID(),
            members: [],
            areas: [],
            sharedCalendarID: "household@example.com"
        )
        let draft = ManualDraftFactory.makeDraft(
            title: "Wash the dog",
            dueDate: Date(timeIntervalSince1970: 1_800_086_400),
            amount: nil,
            ownerID: nil,
            areaID: nil,
            recurrence: .monthly
        )
        let calendar = RecordingCalendarClient(result: .success(CalendarEventReference(id: "event-dog", url: nil)))
        let service = HouseholdApprovalService(calendar: calendar, appBaseURL: URL(string: "household://drafts")!)

        let approved = await service.approve(draft, in: household)

        XCTAssertEqual(approved.status, .approved)
        XCTAssertNil(calendar.createdEvents[0].notes.split(separator: "\n").first(where: { $0.contains("Amount:") }))
        XCTAssertEqual(calendar.createdEvents[0].recurrenceRule, "RRULE:FREQ=MONTHLY")
        XCTAssertTrue(calendar.createdEvents[0].notes.contains("Repeat: Every month"))
    }

    func testCalendarFailureLeavesDraftPendingRetry() async {
        let owner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Marco", email: "marco@example.com")
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [owner],
            areas: [],
            sharedCalendarID: "household@example.com"
        )
        let draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-fail",
                subject: "Failed calendar write",
                from: "sender@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "Needs a retry."
            ),
            title: "Retry me",
            dueDate: Date(timeIntervalSince1970: 1_800_172_800),
            amount: nil,
            ownerID: owner.id,
            areaID: nil,
            extractionConfidence: 0.5,
            evidence: []
        )
        let calendar = RecordingCalendarClient(result: .failure(CalendarClientError.creationFailed("quota")))
        let service = HouseholdApprovalService(calendar: calendar, appBaseURL: URL(string: "household://drafts")!)

        let result = await service.approve(draft, in: household)

        XCTAssertEqual(result.status, .calendarRetryRequired)
        XCTAssertNil(result.googleEventID)
        XCTAssertEqual(result.lastError, "quota")
    }

    func testRejectedDraftDoesNotCreateCalendarEvent() async {
        let owner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Marco", email: "marco@example.com")
        let household = HouseholdContext(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
            members: [owner],
            areas: [],
            sharedCalendarID: "household@example.com"
        )
        let draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-reject",
                subject: "FYI only",
                from: "sender@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "No action needed."
            ),
            title: "FYI only",
            dueDate: nil,
            amount: nil,
            ownerID: owner.id,
            areaID: nil,
            extractionConfidence: 0.33,
            evidence: []
        )
        let calendar = RecordingCalendarClient(result: .success(CalendarEventReference(id: "unexpected", url: nil)))
        let service = HouseholdApprovalService(calendar: calendar, appBaseURL: URL(string: "household://drafts")!)

        let rejected = service.reject(draft, reason: "No household action")

        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertEqual(rejected.lastError, "No household action")
        XCTAssertTrue(calendar.createdEvents.isEmpty)
        XCTAssertEqual(household.sharedCalendarID, "household@example.com")
    }

    func testDeletedCalendarEventMarksDraftChangedExternally() async {
        var draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-deleted",
                subject: "Deleted event",
                from: "sender@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "Watch for deletion."
            ),
            title: "Deleted later",
            dueDate: Date(timeIntervalSince1970: 1_800_172_800),
            amount: nil,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.7,
            evidence: []
        )
        draft.status = .approved
        draft.googleEventID = "event-deleted"
        let calendar = RecordingCalendarClient(result: .success(CalendarEventReference(id: "unused", url: nil)))
        calendar.eventStatuses["event-deleted"] = .deleted
        let service = HouseholdApprovalService(calendar: calendar, appBaseURL: URL(string: "household://drafts")!)

        let reconciled = await service.reconcileCalendarState(for: draft)

        XCTAssertEqual(reconciled.status, .changedExternally)
        XCTAssertEqual(reconciled.lastError, "Google Calendar event was deleted externally.")
    }
}

private final class RecordingCalendarClient: CalendarClient, @unchecked Sendable {
    var createdEvents: [CalendarEventDraft] = []
    var eventStatuses: [String: CalendarEventSyncState] = [:]
    private let result: Result<CalendarEventReference, Error>

    init(result: Result<CalendarEventReference, Error>) {
        self.result = result
    }

    func createEvent(_ event: CalendarEventDraft) async throws -> CalendarEventReference {
        createdEvents.append(event)
        return try result.get()
    }

    func eventStatus(for eventID: String) async throws -> CalendarEventSyncState {
        eventStatuses[eventID] ?? .present
    }
}
