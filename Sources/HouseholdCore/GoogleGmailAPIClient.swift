import Foundation

public protocol GoogleAccessTokenProvider: Sendable {
    func accessToken() async throws -> String
}

public protocol GoogleHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionGoogleHTTPTransport: GoogleHTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAPIClientError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public enum GoogleAPIClientError: Error, Equatable, LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case missingLabel(String)
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Google returned a non-HTTP response."
        case .httpStatus(let statusCode):
            "Google API request failed with HTTP \(statusCode)."
        case .missingLabel(let label):
            "Gmail label '\(label)' was not found."
        case .invalidURL:
            "Could not build a Google API URL."
        }
    }
}

public final class GoogleGmailAPIClient: GmailClient, GmailDraftClient, Sendable {
    public static let householdDiscoveryQuery = """
    newer_than:180d (bill OR invoice OR due OR renewal OR payment OR subscription OR appointment OR reminder OR rent OR insurance OR tax OR school OR dentist OR doctor OR maintenance OR repair)
    """

    private let tokenProvider: GoogleAccessTokenProvider
    private let transport: GoogleHTTPTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let maxResults: Int

    public init(
        tokenProvider: GoogleAccessTokenProvider,
        transport: GoogleHTTPTransport = URLSessionGoogleHTTPTransport(),
        maxResults: Int = 10
    ) {
        self.tokenProvider = tokenProvider
        self.transport = transport
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.maxResults = maxResults
    }

    public func messages(labeled label: String) async throws -> [SourceEmail] {
        let accessToken = try await tokenProvider.accessToken()
        let labels = try await gmailLabels(accessToken: accessToken)

        if let targetLabel = labels.first(where: { $0.name == label }) {
            return try await sourceEmails(
                ids: messageIDs(labelID: targetLabel.id, accessToken: accessToken),
                label: label,
                accessToken: accessToken
            )
        }

        return try await sourceEmails(
            ids: messageIDs(query: Self.householdDiscoveryQuery, accessToken: accessToken),
            label: "Auto Household",
            accessToken: accessToken
        )
    }

    public func saveDraft(_ reply: GmailReplyDraft, existingDraftID: String?) async throws -> GmailDraftReference {
        let accessToken = try await tokenProvider.accessToken()
        let path: String
        let method: String

        if let existingDraftID, !existingDraftID.isEmpty {
            path = "/gmail/v1/users/me/drafts/\(encodedPathSegment(existingDraftID))"
            method = "PUT"
        } else {
            path = "/gmail/v1/users/me/drafts"
            method = "POST"
        }

        var request = try authorizedRequest(path: path, accessToken: accessToken)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            GmailDraftRequest(message: GmailDraftRawMessage(raw: encodedMIMEMessage(for: reply)))
        )

        let response: GmailDraftResponse = try await perform(request)
        return GmailDraftReference(id: response.id, messageID: response.message?.id)
    }

    private func sourceEmails(ids: [String], label: String, accessToken: String) async throws -> [SourceEmail] {
        var messages: [SourceEmail] = []

        for id in ids {
            let message = try await messageMetadata(id: id, accessToken: accessToken)
            messages.append(try GmailMessageMapper.sourceEmail(from: message, label: label))
        }

        return messages
    }

    private func gmailLabels(accessToken: String) async throws -> [GmailAPILabel] {
        var request = try authorizedRequest(path: "/gmail/v1/users/me/labels", accessToken: accessToken)
        request.httpMethod = "GET"
        let response: GmailLabelListResponse = try await perform(request)
        return response.labels
    }

    private func messageIDs(labelID: String, accessToken: String) async throws -> [String] {
        var components = apiComponents(path: "/gmail/v1/users/me/messages")
        components.queryItems = [
            URLQueryItem(name: "labelIds", value: labelID),
            URLQueryItem(name: "maxResults", value: "\(maxResults)")
        ]

        return try await messageIDs(components: components, accessToken: accessToken)
    }

    private func messageIDs(query: String, accessToken: String) async throws -> [String] {
        var components = apiComponents(path: "/gmail/v1/users/me/messages")
        components.queryItems = [
            URLQueryItem(name: "q", value: query.replacingOccurrences(of: "\n", with: " ")),
            URLQueryItem(name: "maxResults", value: "\(maxResults)")
        ]

        return try await messageIDs(components: components, accessToken: accessToken)
    }

    private func messageIDs(components: URLComponents, accessToken: String) async throws -> [String] {
        guard let url = components.url else {
            throw GoogleAPIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let response: GmailMessageListResponse = try await perform(request)
        return response.messages.map(\.id)
    }

    private func messageMetadata(id: String, accessToken: String) async throws -> GmailAPIMessage {
        var components = apiComponents(path: "/gmail/v1/users/me/messages/\(id)")
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "From")
        ]

        guard let url = components.url else {
            throw GoogleAPIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func authorizedRequest(path: String, accessToken: String) throws -> URLRequest {
        let components = apiComponents(path: path)
        guard let url = components.url else {
            throw GoogleAPIClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func apiComponents(path: String) -> URLComponents {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "gmail.googleapis.com"
        components.path = path
        return components
    }

    private func encodedPathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func encodedMIMEMessage(for reply: GmailReplyDraft) -> String {
        let recipient = headerSafe(reply.to)
        let subject = headerSafe(reply.subject)
        let body = reply.body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let mime = [
            "To: \(recipient)",
            "Subject: \(subject)",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=utf-8",
            "Content-Transfer-Encoding: 8bit",
            "",
            body
        ].joined(separator: "\r\n")

        return Data(mime.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func headerSafe(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleAPIClientError.httpStatus(response.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct GmailDraftRequest: Codable, Sendable {
    var message: GmailDraftRawMessage
}

private struct GmailDraftRawMessage: Codable, Sendable {
    var raw: String
}

private struct GmailDraftResponse: Codable, Sendable {
    var id: String
    var message: GmailDraftResponseMessage?
}

private struct GmailDraftResponseMessage: Codable, Sendable {
    var id: String
}

private struct GmailAPILabel: Equatable, Codable, Sendable {
    var id: String
    var name: String
}

private struct GmailLabelListResponse: Equatable, Codable, Sendable {
    var labels: [GmailAPILabel]
}

private struct GmailMessageListResponse: Equatable, Codable, Sendable {
    var messages: [GmailMessageID]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = try container.decodeIfPresent([GmailMessageID].self, forKey: .messages) ?? []
    }
}

private struct GmailMessageID: Equatable, Codable, Sendable {
    var id: String
}
