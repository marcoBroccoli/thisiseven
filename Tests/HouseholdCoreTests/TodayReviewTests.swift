import XCTest
@testable import HouseholdCore

final class TodayReviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTodayReviewGroupsActionableDraftsWithoutDuplicates() {
        var sync = makeDraft(title: "Sync me", dueOffset: 86_400)
        sync.status = .calendarUpdateRequired
        let overdue = makeDraft(title: "Overdue bill", dueOffset: -86_400)
        let dueToday = makeDraft(title: "Due today", dueOffset: 3_600)
        var waiting = makeDraft(title: "Waiting landlord", dueOffset: 3 * 86_400)
        waiting.triageState = .waiting
        var reply = makeDraft(title: "Reply school", dueOffset: 4 * 86_400, bodyPreview: "Please reply to confirm.")
        reply.replyStatus = .needsReply
        var done = makeDraft(title: "Done", dueOffset: 0)
        done.triageState = .done
        var approved = makeDraft(title: "Approved", dueOffset: 0)
        approved.status = .approved

        let sections = TodayReviewModel(
            drafts: [approved, done, reply, waiting, dueToday, overdue, sync],
            household: HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: nil),
            now: now
        ).sections

        XCTAssertEqual(sections.map(\.title), ["Calendar Attention", "Overdue", "Due Today", "Waiting", "Needs Reply"])
        XCTAssertEqual(sections.flatMap(\.drafts).map(\.title), ["Sync me", "Overdue bill", "Due today", "Waiting landlord", "Reply school"])
    }

    func testTodayReviewDoesNotSurfaceManuallySentReplies() {
        var reply = makeDraft(title: "Reply school", dueOffset: 4 * 86_400, bodyPreview: "Please reply to confirm.")
        reply.replyStatus = .sentManually

        let sections = TodayReviewModel(
            drafts: [reply],
            household: HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: nil),
            now: now
        ).sections

        XCTAssertTrue(sections.isEmpty)
    }

    func testTodayReviewHidesDeferredWorkUntilItsReturnTime() {
        var draft = makeDraft(title: "Pay water bill", dueOffset: 3 * 3_600)
        draft.snoozedUntil = now.addingTimeInterval(60 * 60)
        let household = HouseholdContext(id: UUID(), members: [], areas: [], sharedCalendarID: nil)

        let deferredSections = TodayReviewModel(drafts: [draft], household: household, now: now).sections
        let returnedSections = TodayReviewModel(
            drafts: [draft],
            household: household,
            now: now.addingTimeInterval(60 * 60)
        ).sections

        XCTAssertTrue(deferredSections.isEmpty)
        XCTAssertEqual(returnedSections.map(\.title), ["Due Today"])
        XCTAssertEqual(draft.dueDate, now.addingTimeInterval(3 * 3_600))
    }

    private func makeDraft(title: String, dueOffset: TimeInterval, bodyPreview: String = "Household task") -> InboxDraft {
        InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-\(title)",
                subject: title,
                from: "sender@example.com",
                receivedAt: now,
                label: "HouseholdTodo",
                bodyPreview: bodyPreview
            ),
            title: title,
            dueDate: now.addingTimeInterval(dueOffset),
            amount: nil,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: []
        )
    }
}
