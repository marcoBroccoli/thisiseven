import XCTest
@testable import HouseholdCore

final class LocalReminderPlanningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPlannerSchedulesOpenDraftAtPolicyReminderTimes() {
        let dueDate = now.addingTimeInterval(4 * 86_400)
        let draft = makeDraft(title: "Pay water bill", dueDate: dueDate, status: .pendingApproval)

        let plans = LocalReminderPlanner.plans(drafts: [draft], household: household(), now: now)

        XCTAssertEqual(plans.map(\.minutesBeforeDue), [2_880, 1_440])
        XCTAssertEqual(plans.map(\.triggerDate), [
            dueDate.addingTimeInterval(-2_880 * 60),
            dueDate.addingTimeInterval(-1_440 * 60)
        ])
        XCTAssertEqual(plans.map(\.draftID), [draft.id, draft.id])
    }

    func testPlannerExcludesApprovedClosedAndPastDrafts() {
        var approved = makeDraft(title: "Calendar event", dueDate: now.addingTimeInterval(4 * 86_400), status: .approved)
        approved.googleEventID = "calendar-event"
        var done = makeDraft(title: "Already done", dueDate: now.addingTimeInterval(4 * 86_400), status: .pendingApproval)
        done.triageState = .done
        let past = makeDraft(title: "Past due", dueDate: now.addingTimeInterval(-86_400), status: .pendingApproval)

        let plans = LocalReminderPlanner.plans(drafts: [approved, done, past], household: household(), now: now)

        XCTAssertEqual(plans, [])
    }

    func testPlannerSkipsReminderTimesThatHaveAlreadyPassed() {
        let dueDate = now.addingTimeInterval(5 * 60)
        let draft = makeDraft(title: "Urgent task", dueDate: dueDate, status: .pendingApproval)

        let plans = LocalReminderPlanner.plans(drafts: [draft], household: household(), now: now)

        XCTAssertEqual(plans, [])
    }

    func testPlannerSchedulesOneReturnAlertForDeferredWork() {
        let dueDate = now.addingTimeInterval(4 * 86_400)
        let returnTime = now.addingTimeInterval(3 * 3_600)
        var draft = makeDraft(title: "Pay water bill", dueDate: dueDate, status: .pendingApproval)
        draft.snoozedUntil = returnTime

        let plans = LocalReminderPlanner.plans(drafts: [draft], household: household(), now: now)

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].draftID, draft.id)
        XCTAssertEqual(plans[0].triggerDate, returnTime)
        XCTAssertEqual(plans[0].minutesBeforeDue, 0)
        XCTAssertEqual(plans[0].title, "Back on your list")
        XCTAssertEqual(draft.dueDate, dueDate)
    }

    private func household() -> HouseholdContext {
        HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: "primary")
    }

    private func makeDraft(title: String, dueDate: Date, status: InboxDraftStatus) -> InboxDraft {
        var draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "message-\(title)",
                subject: title,
                from: "billing@example.com",
                receivedAt: now,
                label: "Auto Household",
                bodyPreview: "Please pay this household bill."
            ),
            title: title,
            dueDate: dueDate,
            amount: Decimal(42),
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.9,
            evidence: []
        )
        draft.status = status
        return draft
    }
}
