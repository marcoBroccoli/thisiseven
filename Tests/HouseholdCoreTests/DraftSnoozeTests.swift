import Foundation
import XCTest
@testable import HouseholdCore

final class DraftSnoozeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFutureSnoozeIsCurrentlySnoozed() {
        var draft = makeDraft()
        draft.snoozedUntil = now.addingTimeInterval(60 * 60)

        XCTAssertTrue(DraftSnoozeService.isCurrentlySnoozed(draft, now: now))
    }

    func testMissingOrExpiredSnoozeIsNotCurrentlySnoozed() {
        let activeDraft = makeDraft()
        var expiredDraft = makeDraft()
        expiredDraft.snoozedUntil = now.addingTimeInterval(-1)

        XCTAssertFalse(DraftSnoozeService.isCurrentlySnoozed(activeDraft, now: now))
        XCTAssertFalse(DraftSnoozeService.isCurrentlySnoozed(expiredDraft, now: now))
    }

    func testDraftWithoutSnoozeMetadataDecodesFromLegacyJSON() throws {
        let draft = makeDraft()
        let encodedDraft = try JSONEncoder().encode(draft)
        var legacyPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedDraft) as? [String: Any]
        )
        legacyPayload.removeValue(forKey: "snoozedUntil")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)

        let decodedDraft = try JSONDecoder().decode(InboxDraft.self, from: legacyData)

        XCTAssertEqual(decodedDraft, draft)
        XCTAssertNil(decodedDraft.snoozedUntil)
    }

    private func makeDraft() -> InboxDraft {
        InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "snooze-email",
                subject: "Book the plumber",
                from: "home@example.com",
                receivedAt: now,
                label: "Auto Household",
                bodyPreview: "Please arrange a visit."
            ),
            title: "Book the plumber",
            dueDate: nil,
            amount: nil,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: []
        )
    }
}
