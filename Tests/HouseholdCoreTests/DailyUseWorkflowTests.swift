import XCTest
@testable import HouseholdCore

final class DailyUseWorkflowTests: XCTestCase {
    func testLocalStateDoesNotMergeIgnoredSenderImports() {
        let state = LocalHouseholdState(
            drafts: [],
            replyDrafts: [],
            ignoredSenders: [IgnoredSenderRule(value: "billing@noise.example")]
        )
        let ignored = makeDraft(title: "Noise", from: "billing@noise.example")
        let kept = makeDraft(title: "Real bill", from: "billing@water.example")

        let merged = state.mergingImportedDrafts([ignored, kept])

        XCTAssertEqual(merged.drafts.map(\.title), ["Real bill"])
    }

    func testImportMergePreservesDoneAndNotHouseholdDecisions() {
        var done = makeDraft(title: "Old bill", gmailMessageID: "gmail-old")
        done.triageState = .done
        var notHousehold = makeDraft(title: "Promo", gmailMessageID: "gmail-promo")
        notHousehold.triageState = .notHousehold
        let state = LocalHouseholdState(drafts: [done, notHousehold])

        let merged = state.mergingImportedDrafts([
            makeDraft(title: "Old bill from Gmail", gmailMessageID: "gmail-old"),
            makeDraft(title: "Promo from Gmail", gmailMessageID: "gmail-promo")
        ])

        XCTAssertEqual(merged.drafts.count, 2)
        XCTAssertEqual(merged.drafts[0].triageState, .done)
        XCTAssertEqual(merged.drafts[1].triageState, .notHousehold)
    }

    func testInboxBucketsHideClosedDraftsAndExposeWaiting() {
        var done = makeDraft(title: "Done", gmailMessageID: "gmail-done")
        done.triageState = .done
        var notHousehold = makeDraft(title: "Not household", gmailMessageID: "gmail-noise")
        notHousehold.triageState = .notHousehold
        var waiting = makeDraft(title: "Waiting on landlord", gmailMessageID: "gmail-waiting")
        waiting.triageState = .waiting
        let active = makeDraft(title: "Active bill", gmailMessageID: "gmail-active")
        let model = InboxPresentationModel(drafts: [done, notHousehold, waiting, active])

        let buckets = model.triageBuckets(
            household: HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: nil),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(buckets.map(\.title), ["Waiting", "Urgent"])
        XCTAssertEqual(buckets.flatMap(\.drafts).map(\.title), ["Waiting on landlord", "Active bill"])
    }

    func testReplyWorkflowStatusIsStoredOnDraft() {
        var draft = makeDraft(title: "Please reply", gmailMessageID: "gmail-reply")

        draft.replyStatus = .copied

        XCTAssertEqual(draft.replyStatus, .copied)
    }

    func testIgnoredSenderMatchesCaseInsensitively() {
        let rule = IgnoredSenderRule(value: "Billing@Noise.Example")

        XCTAssertTrue(rule.matches(sender: "billing@noise.example"))
        XCTAssertFalse(rule.matches(sender: "alerts@noise.example"))
    }

    private func makeDraft(
        title: String,
        gmailMessageID: String = UUID().uuidString,
        from: String = "sender@example.com"
    ) -> InboxDraft {
        InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: gmailMessageID,
                subject: title,
                from: from,
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "Auto Household",
                bodyPreview: "Payment due today."
            ),
            title: title,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            amount: Decimal(20),
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: []
        )
    }
}
