import XCTest
@testable import HouseholdCore

final class GoogleIntegrationTests: XCTestCase {
    func testPKCEChallengeUsesRFC7636Example() throws {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        let challenge = GoogleOAuthPKCE.codeChallenge(for: verifier)

        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testOAuthAuthorizationURLIncludesInstalledAppParametersAndScopes() throws {
        let configuration = GoogleOAuthConfiguration(
            clientID: "client-123.apps.googleusercontent.com",
            redirectURI: GoogleOAuthRedirectURI.loopback(port: 54_321).absoluteString,
            scopes: [.gmailReadonly, .gmailCompose, .calendarEvents, .openid, .email, .profile]
        )

        let url = try GoogleOAuthRequestFactory.authorizationURL(
            configuration: configuration,
            state: "state-abc",
            codeChallenge: "challenge-xyz"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "accounts.google.com")
        XCTAssertEqual(components.path, "/o/oauth2/v2/auth")
        XCTAssertEqual(query["client_id"], "client-123.apps.googleusercontent.com")
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:54321")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["access_type"], "offline")
        XCTAssertEqual(query["prompt"], "consent")
        XCTAssertEqual(query["state"], "state-abc")
        XCTAssertEqual(query["code_challenge"], "challenge-xyz")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertTrue(query["scope"]?.contains("https://www.googleapis.com/auth/gmail.readonly") == true)
        XCTAssertTrue(query["scope"]?.contains("https://www.googleapis.com/auth/gmail.compose") == true)
        XCTAssertTrue(query["scope"]?.contains("https://www.googleapis.com/auth/calendar.events") == true)
    }

    func testAuthorizationCodeTokenRequestDoesNotUseClientSecret() throws {
        let configuration = GoogleOAuthConfiguration(
            clientID: "client-123.apps.googleusercontent.com",
            redirectURI: GoogleOAuthRedirectURI.loopback(port: 54_321).absoluteString,
            scopes: [.gmailReadonly]
        )

        let request = try GoogleOAuthTokenRequestFactory.authorizationCodeRequest(
            configuration: configuration,
            code: "auth-code",
            codeVerifier: "verifier-123"
        )
        let body = try formBody(from: request)

        XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(body["client_id"], "client-123.apps.googleusercontent.com")
        XCTAssertEqual(body["code"], "auth-code")
        XCTAssertEqual(body["code_verifier"], "verifier-123")
        XCTAssertEqual(body["grant_type"], "authorization_code")
        XCTAssertEqual(body["redirect_uri"], "http://127.0.0.1:54321")
        XCTAssertNil(body["client_secret"])
    }

    func testAuthorizationCodeTokenRequestIncludesClientSecretWhenConfigured() throws {
        let configuration = GoogleOAuthConfiguration(
            clientID: "client-123.apps.googleusercontent.com",
            clientSecret: "secret-123",
            redirectURI: GoogleOAuthRedirectURI.loopback(port: 54_321).absoluteString,
            scopes: [.gmailReadonly]
        )

        let request = try GoogleOAuthTokenRequestFactory.authorizationCodeRequest(
            configuration: configuration,
            code: "auth-code",
            codeVerifier: "verifier-123"
        )
        let body = try formBody(from: request)

        XCTAssertEqual(body["client_secret"], "secret-123")
        XCTAssertEqual(body["client_id"], "client-123.apps.googleusercontent.com")
        XCTAssertEqual(body["grant_type"], "authorization_code")
    }

    func testRefreshTokenRequestDoesNotUseClientSecret() throws {
        let request = try GoogleOAuthTokenRequestFactory.refreshTokenRequest(
            clientID: "client-123.apps.googleusercontent.com",
            refreshToken: "refresh-456"
        )
        let body = try formBody(from: request)

        XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(body["client_id"], "client-123.apps.googleusercontent.com")
        XCTAssertEqual(body["refresh_token"], "refresh-456")
        XCTAssertEqual(body["grant_type"], "refresh_token")
        XCTAssertNil(body["client_secret"])
    }

    func testRefreshTokenRequestIncludesClientSecretWhenConfigured() throws {
        let request = try GoogleOAuthTokenRequestFactory.refreshTokenRequest(
            clientID: "client-123.apps.googleusercontent.com",
            clientSecret: "secret-123",
            refreshToken: "refresh-456"
        )
        let body = try formBody(from: request)

        XCTAssertEqual(body["client_id"], "client-123.apps.googleusercontent.com")
        XCTAssertEqual(body["client_secret"], "secret-123")
        XCTAssertEqual(body["refresh_token"], "refresh-456")
        XCTAssertEqual(body["grant_type"], "refresh_token")
    }

    func testGmailMetadataMapsToSourceEmail() throws {
        let message = GmailAPIMessage(
            id: "msg-123",
            snippet: "Invoice is due on Friday.",
            internalDateMilliseconds: "1800000000000",
            headers: [
                GmailAPIHeader(name: "Subject", value: "Invoice due"),
                GmailAPIHeader(name: "From", value: "billing@example.com")
            ]
        )

        let source = try GmailMessageMapper.sourceEmail(from: message, label: "HouseholdTodo")

        XCTAssertEqual(source.gmailMessageID, "msg-123")
        XCTAssertEqual(source.subject, "Invoice due")
        XCTAssertEqual(source.from, "billing@example.com")
        XCTAssertEqual(source.bodyPreview, "Invoice is due on Friday.")
        XCTAssertEqual(source.label, "HouseholdTodo")
        XCTAssertEqual(source.receivedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testGmailClientImportsOnlyMessagesFromNamedLabel() async throws {
        let transport = RecordingGoogleHTTPTransport(routes: [
            "GET https://gmail.googleapis.com/gmail/v1/users/me/labels": #"{"labels":[{"id":"Label_123","name":"HouseholdTodo"},{"id":"INBOX","name":"INBOX"}]}"#,
            "GET https://gmail.googleapis.com/gmail/v1/users/me/messages?labelIds=Label_123&maxResults=10": #"{"messages":[{"id":"msg-1"},{"id":"msg-2"}]}"#,
            "GET https://gmail.googleapis.com/gmail/v1/users/me/messages/msg-1?format=metadata&metadataHeaders=Subject&metadataHeaders=From": #"{"id":"msg-1","snippet":"Pay internet bill by Friday.","internalDate":"1800000000000","payload":{"headers":[{"name":"Subject","value":"Internet bill"},{"name":"From","value":"billing@example.com"}]}}"#,
            "GET https://gmail.googleapis.com/gmail/v1/users/me/messages/msg-2?format=metadata&metadataHeaders=Subject&metadataHeaders=From": #"{"id":"msg-2","snippet":"Renew shared subscription.","internalDate":"1800000864000","payload":{"headers":[{"name":"Subject","value":"Subscription renewal"},{"name":"From","value":"accounts@example.com"}]}}"#
        ])
        let client = GoogleGmailAPIClient(
            tokenProvider: StaticGoogleAccessTokenProvider(token: "access-token"),
            transport: transport
        )

        let messages = try await client.messages(labeled: "HouseholdTodo")

        XCTAssertEqual(messages.map(\.gmailMessageID), ["msg-1", "msg-2"])
        XCTAssertEqual(messages.map(\.subject), ["Internet bill", "Subscription renewal"])
        XCTAssertEqual(messages.map(\.label), ["HouseholdTodo", "HouseholdTodo"])
        XCTAssertEqual(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, Array(repeating: "Bearer access-token", count: 4))
    }

    func testGmailClientDiscoversHouseholdMessagesWhenLabelIsMissing() async throws {
        let transport = RecordingGoogleHTTPTransport(routes: [
            "GET https://gmail.googleapis.com/gmail/v1/users/me/labels": #"{"labels":[{"id":"INBOX","name":"INBOX"}]}"#,
            "GET \(gmailMessagesURL(query: GoogleGmailAPIClient.householdDiscoveryQuery, maxResults: 10))": #"{"messages":[{"id":"msg-bill"}]}"#,
            "GET https://gmail.googleapis.com/gmail/v1/users/me/messages/msg-bill?format=metadata&metadataHeaders=Subject&metadataHeaders=From": #"{"id":"msg-bill","snippet":"Your electricity bill of 84.25 is due tomorrow.","internalDate":"1800000000000","payload":{"headers":[{"name":"Subject","value":"Electricity bill due tomorrow"},{"name":"From","value":"billing@energy.example"}]}}"#
        ])
        let client = GoogleGmailAPIClient(
            tokenProvider: StaticGoogleAccessTokenProvider(token: "access-token"),
            transport: transport
        )

        let messages = try await client.messages(labeled: "HouseholdTodo")

        XCTAssertEqual(messages.map(\.gmailMessageID), ["msg-bill"])
        XCTAssertEqual(messages[0].label, "Auto Household")
        XCTAssertEqual(messages[0].subject, "Electricity bill due tomorrow")
    }

    func testGmailClientCreatesDraftWithBase64URLMIMEMessage() async throws {
        let transport = RecordingGoogleHTTPTransport(routes: [
            "POST https://gmail.googleapis.com/gmail/v1/users/me/drafts": #"{"id":"draft-123","message":{"id":"message-123"}}"#
        ])
        let client = GoogleGmailAPIClient(
            tokenProvider: StaticGoogleAccessTokenProvider(token: "access-token"),
            transport: transport
        )

        let reference = try await client.saveDraft(
            GmailReplyDraft(
                to: "office@example.com",
                subject: "Re: School form",
                body: "Hi,\n\nConfirmed."
            ),
            existingDraftID: nil
        )

        XCTAssertEqual(reference.id, "draft-123")
        XCTAssertEqual(reference.messageID, "message-123")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let request = try JSONDecoder().decode(GmailDraftRequestPayload.self, from: body)
        let raw = try XCTUnwrap(Data(base64URLEncoded: request.message.raw))
        let mime = try XCTUnwrap(String(data: raw, encoding: .utf8))
        XCTAssertTrue(mime.contains("To: office@example.com"))
        XCTAssertTrue(mime.contains("Subject: Re: School form"))
        XCTAssertTrue(mime.contains("Hi,\r\n\r\nConfirmed."))
    }

    func testCalendarPayloadUsesHouseholdApprovalFields() throws {
        let event = CalendarEventDraft(
            calendarID: "family@example.com",
            title: "Pay rent",
            dueDate: Date(timeIntervalSince1970: 1_800_086_400),
            notes: "Source: Rent email",
            attendeeEmails: ["marco@example.com", "partner@example.com"],
            reminderMinutesBefore: [1_440, 60],
            appURL: URL(string: "household://drafts/abc")!
        )

        let payload = GoogleCalendarPayloadFactory.payload(from: event)

        XCTAssertEqual(payload.summary, "Pay rent")
        XCTAssertEqual(payload.description, "Source: Rent email\n\nOpen in Household Command Center: household://drafts/abc")
        XCTAssertEqual(payload.start.dateTime, "2027-01-16T08:00:00Z")
        XCTAssertEqual(payload.end.dateTime, "2027-01-16T08:30:00Z")
        XCTAssertEqual(payload.attendees.map(\.email), ["marco@example.com", "partner@example.com"])
        XCTAssertEqual(payload.reminders.overrides.map(\.minutes), [1_440, 60])
    }

    func testCalendarClientCreatesEventOnConfiguredCalendar() async throws {
        let transport = RecordingGoogleHTTPTransport(routes: [
            "POST https://www.googleapis.com/calendar/v3/calendars/primary/events?sendUpdates=none": #"{"id":"event-123","htmlLink":"https://calendar.google.com/calendar/event?eid=abc","status":"confirmed"}"#
        ])
        let client = GoogleCalendarAPIClient(
            tokenProvider: StaticGoogleAccessTokenProvider(token: "access-token"),
            transport: transport
        )
        let event = CalendarEventDraft(
            calendarID: "primary",
            title: "Pay rent",
            dueDate: Date(timeIntervalSince1970: 1_800_086_400),
            notes: "Source: Rent email",
            attendeeEmails: [],
            reminderMinutesBefore: [1_440, 60],
            appURL: URL(string: "household://drafts/abc")!
        )

        let reference = try await client.createEvent(event)

        XCTAssertEqual(reference.id, "event-123")
        XCTAssertEqual(reference.url?.absoluteString, "https://calendar.google.com/calendar/event?eid=abc")
        XCTAssertEqual(transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer access-token"])
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let payload = try JSONDecoder().decode(GoogleCalendarPayload.self, from: body)
        XCTAssertEqual(payload.summary, "Pay rent")
        XCTAssertEqual(payload.start.dateTime, "2027-01-16T08:00:00Z")
        XCTAssertEqual(payload.reminders.overrides.map(\.minutes), [1_440, 60])
    }

    func testCalendarClientReportsDeletedEventStatus() async throws {
        let transport = RecordingGoogleHTTPTransport(routes: [
            "GET https://www.googleapis.com/calendar/v3/calendars/primary/events/event-123": #"{"id":"event-123","status":"cancelled"}"#
        ])
        let client = GoogleCalendarAPIClient(
            tokenProvider: StaticGoogleAccessTokenProvider(token: "access-token"),
            transport: transport,
            calendarID: "primary"
        )

        let status = try await client.eventStatus(for: "event-123")

        XCTAssertEqual(status, .deleted)
    }

    func testCalendarClientUpdatesExistingEventOnConfiguredCalendar() async throws {
        let transport = RecordingGoogleHTTPTransport(routes: [
            "PATCH https://www.googleapis.com/calendar/v3/calendars/primary/events/event-123?sendUpdates=none": #"{"id":"event-123","htmlLink":"https://calendar.google.com/calendar/event?eid=updated","status":"confirmed"}"#
        ])
        let client = GoogleCalendarAPIClient(
            tokenProvider: StaticGoogleAccessTokenProvider(token: "access-token"),
            transport: transport,
            calendarID: "primary"
        )
        let event = CalendarEventDraft(
            calendarID: "primary",
            title: "Updated rent",
            dueDate: Date(timeIntervalSince1970: 1_800_172_800),
            notes: "Updated notes",
            attendeeEmails: [],
            reminderMinutesBefore: [60],
            appURL: URL(string: "household://drafts/abc")!
        )

        let reference = try await client.updateEvent(id: "event-123", with: event)

        XCTAssertEqual(reference.id, "event-123")
        XCTAssertEqual(reference.url?.absoluteString, "https://calendar.google.com/calendar/event?eid=updated")
        XCTAssertEqual(transport.requests.first?.httpMethod, "PATCH")
        let body = try XCTUnwrap(transport.requests.first?.httpBody)
        let payload = try JSONDecoder().decode(GoogleCalendarPayload.self, from: body)
        XCTAssertEqual(payload.summary, "Updated rent")
        XCTAssertEqual(payload.start.dateTime, "2027-01-17T08:00:00Z")
    }

    func testCalendarClientFetchesRemoteEventSnapshot() async throws {
        let transport = RecordingGoogleHTTPTransport(routes: [
            "GET https://www.googleapis.com/calendar/v3/calendars/primary/events/event-123": #"{"id":"event-123","htmlLink":"https://calendar.google.com/calendar/event?eid=abc","status":"confirmed","summary":"Remote title","description":"Remote notes","start":{"dateTime":"2027-01-17T08:00:00Z","timeZone":"UTC"}}"#
        ])
        let client = GoogleCalendarAPIClient(
            tokenProvider: StaticGoogleAccessTokenProvider(token: "access-token"),
            transport: transport,
            calendarID: "primary"
        )

        let snapshot = try await client.eventSnapshot(for: "event-123")

        XCTAssertEqual(snapshot?.title, "Remote title")
        XCTAssertEqual(snapshot?.notes, "Remote notes")
        XCTAssertEqual(snapshot?.dueDate, Date(timeIntervalSince1970: 1_800_172_800))
        XCTAssertEqual(snapshot?.url?.absoluteString, "https://calendar.google.com/calendar/event?eid=abc")
    }

    private func formBody(from request: URLRequest) throws -> [String: String] {
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        return Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0].removingPercentEncoding ?? parts[0], parts[1].removingPercentEncoding ?? parts[1])
        })
    }
}

private struct GmailDraftRequestPayload: Decodable {
    var message: GmailDraftRawMessagePayload
}

private struct GmailDraftRawMessagePayload: Decodable {
    var raw: String
}

private extension Data {
    init?(base64URLEncoded value: String) {
        let standardBase64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - standardBase64.count % 4) % 4)
        self.init(base64Encoded: standardBase64 + padding)
    }
}

private func gmailMessagesURL(query: String, maxResults: Int) -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "gmail.googleapis.com"
    components.path = "/gmail/v1/users/me/messages"
    components.queryItems = [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "maxResults", value: "\(maxResults)")
    ]
    return components.url!.absoluteString
}

private struct StaticGoogleAccessTokenProvider: GoogleAccessTokenProvider {
    var token: String

    func accessToken() async throws -> String {
        token
    }
}

private final class RecordingGoogleHTTPTransport: GoogleHTTPTransport, @unchecked Sendable {
    private let routes: [String: String]
    private(set) var requests: [URLRequest] = []

    init(routes: [String: String]) {
        self.routes = routes
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")"
        guard let body = routes[key] else {
            throw TestGoogleHTTPError.unhandledRequest(key)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(body.utf8), response)
    }
}

private enum TestGoogleHTTPError: Error {
    case unhandledRequest(String)
}
