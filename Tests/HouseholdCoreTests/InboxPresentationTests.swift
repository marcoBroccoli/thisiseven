import XCTest
@testable import HouseholdCore

final class InboxPresentationTests: XCTestCase {
    func testInboxPresentationSelectsFirstDraftByDefault() {
        let drafts = [
            makeDraft(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "First", status: .pendingApproval),
            makeDraft(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Second", status: .approved)
        ]

        let model = InboxPresentationModel(drafts: drafts)

        XCTAssertEqual(model.selectedDraft?.title, "First")
        XCTAssertEqual(model.pendingApprovalCount, 1)
        XCTAssertEqual(model.approvedCount, 1)
    }

    func testReplacingSelectedDraftUpdatesCountsAndSelection() {
        var first = makeDraft(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "First", status: .pendingApproval)
        let second = makeDraft(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Second", status: .calendarRetryRequired)
        var model = InboxPresentationModel(drafts: [first, second])
        model.selectDraft(id: second.id)
        first.status = .approved

        model.replaceDraft(first)

        XCTAssertEqual(model.selectedDraft?.id, second.id)
        XCTAssertEqual(model.pendingApprovalCount, 0)
        XCTAssertEqual(model.approvedCount, 1)
        XCTAssertEqual(model.retryRequiredCount, 1)
    }

    func testFinanceObligationCountIncludesDraftsWithAmounts() {
        let bill = makeDraft(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Bill", amount: Decimal(14.99), status: .pendingApproval)
        let chore = makeDraft(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "Book cleaner", amount: nil, status: .pendingApproval)

        let model = InboxPresentationModel(drafts: [bill, chore])

        XCTAssertEqual(model.financeObligationCount, 1)
    }

    func testTriageBucketsExcludeDeferredWorkUntilItReturns() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "Deferred bill",
            status: .pendingApproval
        )
        draft.snoozedUntil = now.addingTimeInterval(3_600)
        let household = HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: nil)
        let model = InboxPresentationModel(drafts: [draft])

        XCTAssertTrue(model.triageBuckets(household: household, now: now).isEmpty)
        XCTAssertFalse(model.triageBuckets(household: household, now: now.addingTimeInterval(3_600)).isEmpty)
    }

    private func makeDraft(id: UUID, title: String, amount: Decimal? = nil, status: InboxDraftStatus) -> InboxDraft {
        var draft = InboxDraft.pending(
            id: id,
            source: SourceEmail(
                gmailMessageID: "msg-\(id.uuidString)",
                subject: title,
                from: "sender@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "Preview"
            ),
            title: title,
            dueDate: Date(timeIntervalSince1970: 1_800_086_400),
            amount: amount,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: []
        )
        draft.status = status
        return draft
    }
}
