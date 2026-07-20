import XCTest
@testable import EvenCore

final class GmailReplyComposerTests: XCTestCase {
    func testCreatesPrefilledReplyURL() throws {
        let reply = try XCTUnwrap(GmailReplyComposer.draft(
            sourceFrom: "Dentist <appointments@example.com>",
            sourceSubject: "Please confirm your appointment",
            body: "Hello,\n\nThat works for us.\n\nBest,"))

        XCTAssertEqual(reply.recipient, "appointments@example.com")
        XCTAssertEqual(reply.subject, "Re: Please confirm your appointment")

        let components = try XCTUnwrap(URLComponents(url: GmailReplyComposer.composeURL(for: reply),
                                                      resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(values["to"]!, "appointments@example.com")
        XCTAssertEqual(values["su"]!, "Re: Please confirm your appointment")
        XCTAssertEqual(values["body"]!, "Hello,\n\nThat works for us.\n\nBest,")
    }

    func testRejectsSenderWithoutEmailAddress() {
        XCTAssertNil(GmailReplyComposer.draft(sourceFrom: "The dentist",
                                               sourceSubject: "Confirm",
                                               body: "Hello"))
    }
}
