import XCTest
@testable import HouseholdCore

final class CalendarReliabilityTests: XCTestCase {
    private let dueDate = Date(timeIntervalSince1970: 1_800_086_400)
    private let laterDueDate = Date(timeIntervalSince1970: 1_800_172_800)

    func testApprovedDraftUpdatesExistingCalendarEventAndRefreshesSnapshot() async {
        var draft = makeApprovedDraft()
        draft.title = "Pay updated rent"
        draft.dueDate = laterDueDate
        draft.status = .calendarUpdateRequired
        let calendar = RecordingReliableCalendarClient()
        calendar.updateResult = CalendarEventReference(id: "event-123", url: URL(string: "https://calendar.google.com/event?eid=updated"))
        let service = HouseholdApprovalService(calendar: calendar, appBaseURL: URL(string: "household://drafts")!)

        let updated = await service.syncExistingCalendarEvent(draft, in: household(), reminderMinutesBefore: [60])

        XCTAssertEqual(updated.status, .approved)
        XCTAssertEqual(updated.googleEventID, "event-123")
        XCTAssertEqual(updated.googleEventURL?.absoluteString, "https://calendar.google.com/event?eid=updated")
        XCTAssertEqual(updated.calendarLastSyncedSnapshot?.title, "Pay updated rent")
        XCTAssertEqual(updated.calendarLastSyncedSnapshot?.dueDate, laterDueDate)
        XCTAssertNil(updated.calendarExternalSnapshot)
        XCTAssertEqual(calendar.updatedEvents.map(\.eventID), ["event-123"])
        XCTAssertEqual(calendar.updatedEvents.first?.event.title, "Pay updated rent")
    }

    func testReconcileCalendarStateStoresExternalSnapshotAndFieldSummary() async {
        var draft = makeApprovedDraft()
        draft.calendarLastSyncedSnapshot = CalendarEventSnapshot(
            title: "Pay rent",
            dueDate: dueDate,
            notes: "Old notes",
            url: URL(string: "https://calendar.google.com/event?eid=old"),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let remote = CalendarEventSnapshot(
            title: "Pay rent tomorrow",
            dueDate: laterDueDate,
            notes: "Old notes",
            url: URL(string: "https://calendar.google.com/event?eid=old"),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let calendar = RecordingReliableCalendarClient()
        calendar.eventStatuses["event-123"] = .modifiedExternally
        calendar.snapshots["event-123"] = remote
        let service = HouseholdApprovalService(calendar: calendar, appBaseURL: URL(string: "household://drafts")!)

        let reconciled = await service.reconcileCalendarState(for: draft)

        XCTAssertEqual(reconciled.status, .changedExternally)
        XCTAssertEqual(reconciled.calendarExternalSnapshot, remote)
        XCTAssertTrue(reconciled.lastError?.contains("Title changed from Pay rent to Pay rent tomorrow") == true)
        XCTAssertTrue(reconciled.lastError?.contains("Due date changed") == true)
    }

    func testAcceptingExternalCalendarVersionCopiesRemoteFields() {
        var draft = makeApprovedDraft()
        let remote = CalendarEventSnapshot(
            title: "Calendar title",
            dueDate: laterDueDate,
            notes: "Remote notes",
            url: URL(string: "https://calendar.google.com/event?eid=remote"),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_200)
        )
        draft.status = .changedExternally
        draft.calendarExternalSnapshot = remote

        let accepted = CalendarConflictResolver.acceptCalendarVersion(for: draft)

        XCTAssertEqual(accepted.title, "Calendar title")
        XCTAssertEqual(accepted.dueDate, laterDueDate)
        XCTAssertEqual(accepted.status, .approved)
        XCTAssertEqual(accepted.calendarLastSyncedSnapshot, remote)
        XCTAssertNil(accepted.calendarExternalSnapshot)
        XCTAssertNil(accepted.lastError)
    }

    private func makeApprovedDraft() -> InboxDraft {
        var draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-rent",
                subject: "Rent reminder",
                from: "rent@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "Rent is due."
            ),
            title: "Pay rent",
            dueDate: dueDate,
            amount: Decimal(1200),
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.9,
            evidence: ["Rent is due."]
        )
        draft.status = .approved
        draft.googleEventID = "event-123"
        draft.googleEventURL = URL(string: "https://calendar.google.com/event?eid=old")
        draft.calendarLastSyncedSnapshot = CalendarEventSnapshot(
            title: draft.title,
            dueDate: dueDate,
            notes: "Old notes",
            url: draft.googleEventURL,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        return draft
    }

    private func household() -> HouseholdContext {
        HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: "primary")
    }
}

private final class RecordingReliableCalendarClient: CalendarClient, @unchecked Sendable {
    var createdEvents: [CalendarEventDraft] = []
    var updatedEvents: [(eventID: String, event: CalendarEventDraft)] = []
    var eventStatuses: [String: CalendarEventSyncState] = [:]
    var snapshots: [String: CalendarEventSnapshot] = [:]
    var updateResult = CalendarEventReference(id: "event-123", url: URL(string: "https://calendar.google.com/event?eid=event-123"))
    var createResult = CalendarEventReference(id: "event-created", url: URL(string: "https://calendar.google.com/event?eid=created"))

    func createEvent(_ event: CalendarEventDraft) async throws -> CalendarEventReference {
        createdEvents.append(event)
        return createResult
    }

    func updateEvent(id eventID: String, with event: CalendarEventDraft) async throws -> CalendarEventReference {
        updatedEvents.append((eventID: eventID, event: event))
        return updateResult
    }

    func eventStatus(for eventID: String) async throws -> CalendarEventSyncState {
        eventStatuses[eventID] ?? .present
    }

    func eventSnapshot(for eventID: String) async throws -> CalendarEventSnapshot? {
        snapshots[eventID]
    }
}
