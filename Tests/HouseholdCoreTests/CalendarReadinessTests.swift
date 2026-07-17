import XCTest
@testable import HouseholdCore

final class CalendarReadinessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testReadinessMarksPendingDraftWithoutDueDateAsNeedsDueDate() {
        let draft = makeDraft(title: "No due date", dueDate: nil, status: .pendingApproval)
        let intelligence = EmailIntelligenceAnalyzer().analyze(draft: draft, household: makeHousehold(), now: now)

        let readiness = CalendarReadinessEvaluator.evaluate(draft: draft, intelligence: intelligence)

        XCTAssertEqual(readiness.state, .needsDueDate)
        XCTAssertFalse(readiness.canApproveToCalendar)
        XCTAssertEqual(readiness.recommendedReminderMinutesBefore, [])
    }

    func testReadinessMarksPendingDraftWithDueDateAsReadyToApprove() {
        let draft = makeDraft(title: "Ready", dueDate: now.addingTimeInterval(3 * 86_400), status: .pendingApproval)
        let intelligence = EmailIntelligenceAnalyzer().analyze(draft: draft, household: makeHousehold(), now: now)

        let readiness = CalendarReadinessEvaluator.evaluate(draft: draft, intelligence: intelligence)

        XCTAssertEqual(readiness.state, .readyToApprove)
        XCTAssertTrue(readiness.canApproveToCalendar)
        XCTAssertEqual(readiness.recommendedReminderMinutesBefore, [2_880, 1_440])
    }

    func testReadinessSurfacesCalendarStatuses() {
        var scheduled = makeDraft(title: "Scheduled", dueDate: now, status: .approved)
        scheduled.googleEventID = "event-1"
        var retry = makeDraft(title: "Retry", dueDate: now, status: .calendarRetryRequired)
        retry.lastError = "quota"
        var external = makeDraft(title: "External", dueDate: now, status: .changedExternally)
        external.lastError = "deleted"
        let rejected = makeDraft(title: "Rejected", dueDate: now, status: .rejected)
        let analyzer = EmailIntelligenceAnalyzer()
        let household = makeHousehold()

        XCTAssertEqual(CalendarReadinessEvaluator.evaluate(draft: scheduled, intelligence: analyzer.analyze(draft: scheduled, household: household, now: now)).state, .scheduled)
        XCTAssertEqual(CalendarReadinessEvaluator.evaluate(draft: retry, intelligence: analyzer.analyze(draft: retry, household: household, now: now)).state, .retryRequired)
        XCTAssertEqual(CalendarReadinessEvaluator.evaluate(draft: external, intelligence: analyzer.analyze(draft: external, household: household, now: now)).state, .externalChange)
        XCTAssertEqual(CalendarReadinessEvaluator.evaluate(draft: rejected, intelligence: analyzer.analyze(draft: rejected, household: household, now: now)).state, .rejected)
    }

    private func makeHousehold() -> HouseholdContext {
        HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: "primary")
    }

    private func makeDraft(title: String, dueDate: Date?, status: InboxDraftStatus) -> InboxDraft {
        var draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-\(title)",
                subject: title,
                from: "sender@example.com",
                receivedAt: now,
                label: "Auto Household",
                bodyPreview: "Please confirm by Monday."
            ),
            title: title,
            dueDate: dueDate,
            amount: nil,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: []
        )
        draft.status = status
        return draft
    }
}
