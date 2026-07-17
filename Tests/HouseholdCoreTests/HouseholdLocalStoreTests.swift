import XCTest
@testable import HouseholdCore

final class HouseholdLocalStoreTests: XCTestCase {
    func testStoreSavesAndLoadsDraftsAndReplyText() throws {
        let url = temporaryFileURL()
        let store = HouseholdLocalStore(fileURL: url)
        let draft = makeDraft(
            gmailMessageID: "gmail-water",
            title: "Pay water bill",
            status: .pendingApproval
        )
        let state = LocalHouseholdState(
            drafts: [draft],
            replyDrafts: [LocalReplyDraft(draftID: draft.id, body: "I will handle this.")],
            lastCalendarSyncAt: Date(timeIntervalSince1970: 1_800_123_456)
        )

        try store.save(state)
        let loaded = try store.load()

        XCTAssertEqual(loaded.drafts, [draft])
        XCTAssertEqual(loaded.replyText(for: draft.id), "I will handle this.")
        XCTAssertEqual(loaded.lastCalendarSyncAt, Date(timeIntervalSince1970: 1_800_123_456))
    }

    func testStoreReturnsEmptyStateWhenFileDoesNotExist() throws {
        let store = HouseholdLocalStore(fileURL: temporaryFileURL())

        let state = try store.load()

        XCTAssertEqual(state.drafts, [])
        XCTAssertEqual(state.replyDrafts, [])
        XCTAssertNil(state.lastCalendarSyncAt)
    }

    func testMergePreservesExistingDraftDecisionsForSameGmailMessage() {
        var existing = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            gmailMessageID: "gmail-water",
            title: "Edited title",
            status: .approved
        )
        existing.googleEventID = "event-123"
        let imported = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
            gmailMessageID: "gmail-water",
            title: "Water bill from Gmail",
            status: .pendingApproval
        )
        let state = LocalHouseholdState(drafts: [existing], replyDrafts: [])

        let merged = state.mergingImportedDrafts([imported])

        XCTAssertEqual(merged.drafts.count, 1)
        XCTAssertEqual(merged.drafts[0].id, existing.id)
        XCTAssertEqual(merged.drafts[0].title, "Edited title")
        XCTAssertEqual(merged.drafts[0].status, .approved)
        XCTAssertEqual(merged.drafts[0].googleEventID, "event-123")
    }

    func testMergeAppendsNewGmailDraftsAndPreservesManualDrafts() {
        let manual = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            gmailMessageID: "manual-1",
            title: "Book plumber",
            status: .pendingApproval
        )
        var newGmail = makeDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            gmailMessageID: "gmail-insurance",
            title: "Insurance renewal",
            status: .pendingApproval
        )
        newGmail.amount = Decimal(129)
        let state = LocalHouseholdState(drafts: [manual], replyDrafts: [])

        let merged = state.mergingImportedDrafts([newGmail])

        XCTAssertEqual(merged.drafts.map(\.title), ["Book plumber", "Insurance renewal"])
        XCTAssertEqual(merged.drafts[1].amount, Decimal(129))
    }

    func testReplacingReplyDraftUpdatesExistingReplyText() {
        let draftID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        var state = LocalHouseholdState(
            drafts: [],
            replyDrafts: [LocalReplyDraft(draftID: draftID, body: "Old")]
        )

        state.setReplyText("New", for: draftID)

        XCTAssertEqual(state.replyDrafts, [LocalReplyDraft(draftID: draftID, body: "New")])
    }

    private func makeDraft(
        id: UUID = UUID(),
        gmailMessageID: String,
        title: String,
        status: InboxDraftStatus
    ) -> InboxDraft {
        var draft = InboxDraft.pending(
            id: id,
            source: SourceEmail(
                gmailMessageID: gmailMessageID,
                subject: title,
                from: "sender@example.com",
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: gmailMessageID.hasPrefix("manual-") ? "Manual" : "Auto Household",
                bodyPreview: "Preview"
            ),
            title: title,
            dueDate: Date(timeIntervalSince1970: 1_800_086_400),
            amount: nil,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: []
        )
        draft.status = status
        return draft
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
