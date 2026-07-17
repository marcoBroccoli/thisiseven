import XCTest
@testable import HouseholdCore

final class GmailReplyWorkflowTests: XCTestCase {
    func testReplyWorkflowStatusAttentionRules() {
        XCTAssertFalse(ReplyWorkflowStatus.none.requiresReplyAction)
        XCTAssertTrue(ReplyWorkflowStatus.needsReply.requiresReplyAction)
        XCTAssertTrue(ReplyWorkflowStatus.drafted.requiresReplyAction)
        XCTAssertTrue(ReplyWorkflowStatus.copied.requiresReplyAction)
        XCTAssertTrue(ReplyWorkflowStatus.openedInGmail.requiresReplyAction)
        XCTAssertTrue(ReplyWorkflowStatus.savedToGmailDraft.requiresReplyAction)
        XCTAssertFalse(ReplyWorkflowStatus.sentManually.requiresReplyAction)
        XCTAssertFalse(ReplyWorkflowStatus.done.requiresReplyAction)
    }

    func testReplyDraftUsesParsedSenderAndReplySubject() {
        let draft = makeDraft(
            subject: "School form confirmation",
            from: "School Office <office@school.example>"
        )

        let reply = GmailReplyComposer.replyDraft(for: draft, body: "Thanks, I confirm.")

        XCTAssertEqual(reply.to, "office@school.example")
        XCTAssertEqual(reply.subject, "Re: School form confirmation")
        XCTAssertEqual(reply.body, "Thanks, I confirm.")
    }

    func testReplyDraftDoesNotDoublePrefixReSubject() {
        let draft = makeDraft(subject: "Re: Dentist appointment", from: "clinic@example.com")

        let reply = GmailReplyComposer.replyDraft(for: draft, body: "Confirmed.")

        XCTAssertEqual(reply.subject, "Re: Dentist appointment")
    }

    func testComposeURLContainsGmailQueryFields() throws {
        let reply = GmailReplyDraft(
            to: "office@school.example",
            subject: "Re: School form",
            body: "Thanks,\nConfirmed."
        )

        let url = GmailReplyComposer.composeURL(for: reply)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "mail.google.com")
        XCTAssertEqual(components.path, "/mail/u/0/")
        XCTAssertEqual(query["view"], "cm")
        XCTAssertEqual(query["fs"], "1")
        XCTAssertEqual(query["to"], "office@school.example")
        XCTAssertEqual(query["su"], "Re: School form")
        XCTAssertEqual(query["body"], "Thanks,\nConfirmed.")
    }

    private func makeDraft(subject: String, from: String) -> InboxDraft {
        InboxDraft.pending(
            source: SourceEmail(
                gmailMessageID: "msg-reply",
                subject: subject,
                from: from,
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000),
                label: "HouseholdTodo",
                bodyPreview: "Please reply to confirm."
            ),
            title: subject,
            dueDate: nil,
            amount: nil,
            ownerID: nil,
            areaID: nil,
            extractionConfidence: 0.8,
            evidence: []
        )
    }
}
