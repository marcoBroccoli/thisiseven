import XCTest
@testable import HouseholdCore

final class HouseholdDashboardTests: XCTestCase {
    func testManualDraftFactoryCreatesPendingHouseholdItemWithoutEmailSource() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let areaID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let dueDate = Date(timeIntervalSince1970: 1_800_086_400)

        let draft = ManualDraftFactory.makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000abcd")!,
            title: "Book plumber",
            dueDate: dueDate,
            amount: Decimal(120),
            ownerID: ownerID,
            areaID: areaID
        )

        XCTAssertEqual(draft.title, "Book plumber")
        XCTAssertEqual(draft.status, .pendingApproval)
        XCTAssertEqual(draft.source.gmailMessageID, "manual-00000000-0000-0000-0000-00000000ABCD")
        XCTAssertEqual(draft.source.label, "Manual")
        XCTAssertEqual(draft.source.from, "Manual entry")
        XCTAssertEqual(draft.dueDate, dueDate)
        XCTAssertEqual(draft.amount, Decimal(120))
        XCTAssertEqual(draft.ownerID, ownerID)
        XCTAssertEqual(draft.areaID, areaID)
    }

    func testManualRecurringDraftCanHaveNoAmount() {
        let dueDate = Date(timeIntervalSince1970: 1_800_086_400)

        let draft = ManualDraftFactory.makeDraft(
            title: "Wash the dog",
            dueDate: dueDate,
            amount: nil,
            ownerID: nil,
            areaID: nil,
            recurrence: .fortnightly
        )

        XCTAssertEqual(draft.title, "Wash the dog")
        XCTAssertEqual(draft.dueDate, dueDate)
        XCTAssertNil(draft.amount)
        XCTAssertEqual(draft.recurrence, .fortnightly)
        XCTAssertEqual(draft.source.label, "Manual")
    }

    func testDashboardBillsDueSoonFiltersAndSortsOpenFinanceItems() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dueSoon = makeDraft(title: "Due soon", dueOffset: 86_400, amount: Decimal(20), status: .pendingApproval)
        let dueLater = makeDraft(title: "Due later", dueOffset: 10 * 86_400, amount: Decimal(30), status: .pendingApproval)
        let noAmount = makeDraft(title: "No amount", dueOffset: 2 * 86_400, amount: nil, status: .pendingApproval)
        let approvedBill = makeDraft(title: "Approved", dueOffset: 3 * 86_400, amount: Decimal(40), status: .approved)
        let retryBill = makeDraft(title: "Retry", dueOffset: 2 * 86_400, amount: Decimal(50), status: .calendarRetryRequired)
        var deferredBill = makeDraft(title: "Deferred", dueOffset: 2 * 86_400, amount: Decimal(70), status: .pendingApproval)
        deferredBill.snoozedUntil = now.addingTimeInterval(3_600)

        let dashboard = HouseholdDashboard(household: makeHousehold(), drafts: [dueLater, retryBill, noAmount, approvedBill, dueSoon, deferredBill], now: now)

        XCTAssertEqual(dashboard.billsDueSoon.map(\.title), ["Due soon", "Retry"])
    }

    func testDashboardWeeklyReviewPrioritizesUnassignedRetriesAndExternalChanges() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let unassigned = makeDraft(title: "Unassigned", dueOffset: 2 * 86_400, ownerID: nil, status: .pendingApproval)
        let retry = makeDraft(title: "Retry", dueOffset: 20 * 86_400, ownerID: UUID(), status: .calendarRetryRequired)
        let external = makeDraft(title: "External", dueOffset: 20 * 86_400, ownerID: UUID(), status: .changedExternally)
        let normalLater = makeDraft(title: "Normal later", dueOffset: 20 * 86_400, ownerID: UUID(), status: .pendingApproval)
        let approved = makeDraft(title: "Approved", dueOffset: 2 * 86_400, ownerID: nil, status: .approved)

        let dashboard = HouseholdDashboard(household: makeHousehold(), drafts: [normalLater, approved, external, retry, unassigned], now: now)

        XCTAssertEqual(dashboard.weeklyReviewItems.map(\.title), ["Unassigned", "External", "Retry"])
    }

    func testDashboardAreaSummariesShowActiveCountAndTotalObligations() {
        let owner = HouseholdMember(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Marco", email: "marco@example.com")
        let utilities = HouseholdArea(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, name: "Utilities", defaultOwnerID: owner.id)
        let admin = HouseholdArea(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, name: "Admin", defaultOwnerID: nil)
        let household = HouseholdContext(id: UUID(), members: [owner], areas: [utilities, admin], sharedCalendarID: "family@example.com")

        let drafts = [
            makeDraft(title: "Water", dueOffset: 86_400, amount: Decimal(20), ownerID: owner.id, areaID: utilities.id, status: .pendingApproval),
            makeDraft(title: "Power", dueOffset: 86_400, amount: Decimal(80), ownerID: owner.id, areaID: utilities.id, status: .calendarRetryRequired),
            makeDraft(title: "Archive", dueOffset: 86_400, amount: Decimal(10), ownerID: owner.id, areaID: utilities.id, status: .approved)
        ]

        let dashboard = HouseholdDashboard(household: household, drafts: drafts, now: Date(timeIntervalSince1970: 1_800_000_000))

        XCTAssertEqual(dashboard.areaSummaries.count, 2)
        XCTAssertEqual(dashboard.areaSummaries[0].areaName, "Utilities")
        XCTAssertEqual(dashboard.areaSummaries[0].defaultOwnerName, "Marco")
        XCTAssertEqual(dashboard.areaSummaries[0].activeItemCount, 2)
        XCTAssertEqual(dashboard.areaSummaries[0].openObligationTotal, Decimal(100))
        XCTAssertEqual(dashboard.areaSummaries[1].areaName, "Admin")
        XCTAssertEqual(dashboard.areaSummaries[1].activeItemCount, 0)
    }

    private func makeHousehold() -> HouseholdContext {
        HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: "family@example.com")
    }

    private func makeDraft(
        title: String,
        dueOffset: TimeInterval,
        amount: Decimal? = nil,
        ownerID: UUID? = UUID(),
        areaID: UUID? = nil,
        status: InboxDraftStatus
    ) -> InboxDraft {
        var draft = InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-\(title)",
                subject: title,
                from: "sender@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: ""
            ),
            title: title,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000 + dueOffset),
            amount: amount,
            ownerID: ownerID,
            areaID: areaID,
            extractionConfidence: 0.8,
            evidence: []
        )
        draft.status = status
        return draft
    }
}
