import Foundation

public final class GoogleCalendarAPIClient: CalendarClient, Sendable {
    private let tokenProvider: GoogleAccessTokenProvider
    private let transport: GoogleHTTPTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let calendarID: String

    public init(
        tokenProvider: GoogleAccessTokenProvider,
        transport: GoogleHTTPTransport = URLSessionGoogleHTTPTransport(),
        calendarID: String = "primary"
    ) {
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.calendarID = calendarID
    }

    public func createEvent(_ event: CalendarEventDraft) async throws -> CalendarEventReference {
        let accessToken = try await tokenProvider.accessToken()
        var components = calendarComponents(path: "/calendar/v3/calendars/\(encodedPathSegment(event.calendarID))/events")
        components.queryItems = [
            URLQueryItem(name: "sendUpdates", value: "none")
        ]

        guard let url = components.url else {
            throw GoogleAPIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(GoogleCalendarPayloadFactory.payload(from: event))

        let response: GoogleCalendarEventResponse = try await perform(request)
        return CalendarEventReference(id: response.id, url: response.htmlLink)
    }

    public func updateEvent(id eventID: String, with event: CalendarEventDraft) async throws -> CalendarEventReference {
        let accessToken = try await tokenProvider.accessToken()
        var components = calendarComponents(path: "/calendar/v3/calendars/\(encodedPathSegment(event.calendarID))/events/\(encodedPathSegment(eventID))")
        components.queryItems = [
            URLQueryItem(name: "sendUpdates", value: "none")
        ]

        guard let url = components.url else {
            throw GoogleAPIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(GoogleCalendarPayloadFactory.payload(from: event))

        let response: GoogleCalendarEventResponse = try await perform(request)
        return CalendarEventReference(id: response.id, url: response.htmlLink)
    }

    public func eventStatus(for eventID: String) async throws -> CalendarEventSyncState {
        let accessToken = try await tokenProvider.accessToken()
        let path = "/calendar/v3/calendars/\(encodedPathSegment(calendarID))/events/\(encodedPathSegment(eventID))"
        var request = try authorizedRequest(path: path, accessToken: accessToken)
        request.httpMethod = "GET"

        do {
            let response: GoogleCalendarEventResponse = try await perform(request)
            return response.status == "cancelled" ? .deleted : .present
        } catch GoogleAPIClientError.httpStatus(404) {
            return .deleted
        }
    }

    public func eventSnapshot(for eventID: String) async throws -> CalendarEventSnapshot? {
        let accessToken = try await tokenProvider.accessToken()
        let path = "/calendar/v3/calendars/\(encodedPathSegment(calendarID))/events/\(encodedPathSegment(eventID))"
        var request = try authorizedRequest(path: path, accessToken: accessToken)
        request.httpMethod = "GET"

        do {
            let response: GoogleCalendarEventResponse = try await perform(request)
            guard response.status != "cancelled" else { return nil }
            guard
                let title = response.summary,
                let dateTime = response.start?.dateTime,
                let dueDate = Self.parseGoogleDate(dateTime)
            else {
                throw GoogleAPIClientError.invalidResponse
            }

            return CalendarEventSnapshot(
                title: title,
                dueDate: dueDate,
                notes: response.description,
                url: response.htmlLink,
                capturedAt: Date()
            )
        } catch GoogleAPIClientError.httpStatus(404) {
            return nil
        }
    }

    private func authorizedRequest(path: String, accessToken: String) throws -> URLRequest {
        let components = calendarComponents(path: path)
        guard let url = components.url else {
            throw GoogleAPIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func calendarComponents(path: String) -> URLComponents {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.percentEncodedPath = path
        return components
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleAPIClientError.httpStatus(response.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func encodedPathSegment(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }

    private static func parseGoogleDate(_ dateTime: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: dateTime)
    }
}

private struct GoogleCalendarEventResponse: Equatable, Codable, Sendable {
    var id: String
    var htmlLink: URL?
    var status: String?
    var summary: String?
    var description: String?
    var start: GoogleCalendarDateTime?
}
