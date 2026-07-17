import XCTest
@testable import EvenCore

final class GoogleConnectTests: XCTestCase {
    func testReversedSchemeAndRedirect() {
        XCTAssertEqual(GoogleConnectConfig.redirectScheme,
                       "com.googleusercontent.apps.733777745150-gb5i361it6sghbc48qlgil58nsojniq7")
        XCTAssertTrue(GoogleConnectConfig.redirectURI.hasSuffix(":/oauth2redirect"))
    }

    func testAttemptBuildsPKCEAuthorizationURL() throws {
        let attempt = GoogleConnectAttempt()
        XCTAssertEqual(attempt.codeVerifier.count, 64)

        let components = try XCTUnwrap(URLComponents(url: attempt.authorizationURL,
                                                     resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "accounts.google.com")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["client_id"], GoogleConnectConfig.iosClientID)
        XCTAssertEqual(items["redirect_uri"], GoogleConnectConfig.redirectURI)
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["response_type"], "code")
        let challenge = try XCTUnwrap(items["code_challenge"])
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertTrue((items["scope"] ?? "").contains("gmail.readonly"))
    }

    func testCallbackCodeExtractionChecksState() {
        let attempt = GoogleConnectAttempt()
        let good = URL(string: "\(GoogleConnectConfig.redirectURI)?state=\(attempt.state)&code=abc123")!
        XCTAssertEqual(attempt.code(from: good), "abc123")
        let badState = URL(string: "\(GoogleConnectConfig.redirectURI)?state=WRONG&code=abc123")!
        XCTAssertNil(attempt.code(from: badState))
    }

    func testEachAttemptIsIndependent() {
        let a = GoogleConnectAttempt(), b = GoogleConnectAttempt()
        XCTAssertNotEqual(a.codeVerifier, b.codeVerifier)
        XCTAssertNotEqual(a.state, b.state)
    }
}
