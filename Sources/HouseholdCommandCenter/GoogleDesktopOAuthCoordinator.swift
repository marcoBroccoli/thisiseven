import AppKit
import Foundation
import HouseholdCore
import Network

enum GoogleDesktopOAuthError: Error, LocalizedError {
    case listenerFailed(String)
    case invalidCallback
    case callbackError(String)
    case stateMismatch
    case missingAuthorizationCode
    case missingRefreshToken
    case browserOpenFailed
    case tokenExchangeFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .listenerFailed(let message):
            "Could not start the local OAuth callback listener: \(message)"
        case .invalidCallback:
            "Google returned an invalid OAuth callback."
        case .callbackError(let message):
            "Google OAuth returned an error: \(message)"
        case .stateMismatch:
            "Google OAuth state did not match this app's request."
        case .missingAuthorizationCode:
            "Google OAuth did not return an authorization code."
        case .missingRefreshToken:
            "Google did not return a refresh token. Try disconnecting access in your Google Account and connect again."
        case .browserOpenFailed:
            "Could not open the Google sign-in page in your browser."
        case .tokenExchangeFailed(let status, let message):
            "Google token exchange failed with HTTP \(status): \(message)"
        }
    }
}

@MainActor
final class GoogleDesktopOAuthCoordinator {
    private let tokenStore: GoogleKeychainTokenStore
    private let transport: GoogleHTTPTransport
    private let decoder = JSONDecoder()

    init(
        tokenStore: GoogleKeychainTokenStore,
        transport: GoogleHTTPTransport = URLSessionGoogleHTTPTransport()
    ) {
        self.tokenStore = tokenStore
        self.transport = transport
    }

    func connect(clientID: String, clientSecret: String?, accountHint: String) async throws -> StoredGoogleTokens {
        let receiver = GoogleOAuthLoopbackReceiver()
        let redirectURI = try await receiver.start()
        defer { receiver.stop() }

        let state = UUID().uuidString
        let verifier = GoogleOAuthPKCE.randomVerifier()
        let configuration = GoogleOAuthConfiguration(
            clientID: clientID,
            clientSecret: clientSecret,
            redirectURI: redirectURI.absoluteString,
            scopes: [.gmailReadonly, .gmailCompose, .calendarEvents, .openid, .email, .profile]
        )
        let authorizationURL = try GoogleOAuthRequestFactory.authorizationURL(
            configuration: configuration,
            state: state,
            codeChallenge: GoogleOAuthPKCE.codeChallenge(for: verifier)
        )

        guard NSWorkspace.shared.open(authorizationURL) else {
            throw GoogleDesktopOAuthError.browserOpenFailed
        }

        let callback = try await receiver.waitForCallback(expectedState: state)
        let request = try GoogleOAuthTokenRequestFactory.authorizationCodeRequest(
            configuration: configuration,
            code: callback.code,
            codeVerifier: verifier
        )
        let response: GoogleOAuthTokenResponse = try await perform(request)

        guard let refreshToken = response.refreshToken else {
            throw GoogleDesktopOAuthError.missingRefreshToken
        }

        let tokens = StoredGoogleTokens(
            clientID: clientID,
            clientSecret: clientSecret?.nilIfBlank,
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            accountHint: accountHint
        )
        try tokenStore.save(tokens)
        return tokens
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let message = GoogleOAuthErrorMessageFormatter.message(from: data)
            throw GoogleDesktopOAuthError.tokenExchangeFailed(response.statusCode, message)
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum GoogleOAuthErrorMessageFormatter {
    static func message(from data: Data) -> String {
        if
            let payload = try? JSONDecoder().decode(GoogleOAuthErrorPayload.self, from: data),
            !payload.error.isEmpty
        {
            if let description = payload.errorDescription, !description.isEmpty {
                return "\(payload.error): \(description)"
            }
            return payload.error
        }

        return String(data: data, encoding: .utf8) ?? "No response body."
    }
}

private struct GoogleOAuthErrorPayload: Decodable {
    var error: String
    var errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private struct GoogleOAuthCallback {
    var code: String
    var state: String
}

private final class GoogleOAuthLoopbackReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "HouseholdCommandCenter.GoogleOAuthLoopback")
    private var listener: NWListener?
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var callbackContinuation: CheckedContinuation<GoogleOAuthCallback, Error>?
    private var expectedState: String?
    private var pendingCallback: GoogleOAuthCallback?
    private var pendingError: Error?

    func start() async throws -> URL {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 0)!)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                guard let port = listener.port else {
                    self.resumeReady(with: .failure(GoogleDesktopOAuthError.listenerFailed("Missing local port.")))
                    return
                }

                let url = GoogleOAuthRedirectURI.loopback(port: port.rawValue)
                self.resumeReady(with: .success(url))
            case .failed(let error):
                self.resumeReady(with: .failure(GoogleDesktopOAuthError.listenerFailed(error.localizedDescription)))
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.start(queue: queue)
        }
    }

    func waitForCallback(expectedState: String) async throws -> GoogleOAuthCallback {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.expectedState = expectedState

                if let pendingError = self.pendingError {
                    self.pendingError = nil
                    continuation.resume(throwing: pendingError)
                    return
                }

                if let callback = self.pendingCallback {
                    self.pendingCallback = nil
                    self.deliver(callback, to: continuation)
                    return
                }

                self.callbackContinuation = continuation
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
            guard let self else { return }
            let result = self.parseCallback(from: data)
            self.respond(to: connection, success: result.isSuccess)
            self.finish(with: result)
        }
    }

    private func parseCallback(from data: Data?) -> Result<GoogleOAuthCallback, Error> {
        guard
            let data,
            let request = String(data: data, encoding: .utf8),
            let requestLine = request.components(separatedBy: "\r\n").first
        else {
            return .failure(GoogleDesktopOAuthError.invalidCallback)
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return .failure(GoogleDesktopOAuthError.invalidCallback)
        }

        guard
            let components = URLComponents(string: "http://127.0.0.1\(parts[1])"),
            components.path == "/" || components.path == "/oauth/callback"
        else {
            return .failure(GoogleDesktopOAuthError.invalidCallback)
        }

        let queryItems = components.queryItems ?? []
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            return .failure(GoogleDesktopOAuthError.callbackError(error))
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            return .failure(GoogleDesktopOAuthError.missingAuthorizationCode)
        }

        let state = queryItems.first(where: { $0.name == "state" })?.value ?? ""
        return .success(GoogleOAuthCallback(code: code, state: state))
    }

    private func finish(with result: Result<GoogleOAuthCallback, Error>) {
        switch result {
        case .success(let callback):
            if let continuation = callbackContinuation {
                callbackContinuation = nil
                deliver(callback, to: continuation)
            } else {
                pendingCallback = callback
            }
        case .failure(let error):
            if let continuation = callbackContinuation {
                callbackContinuation = nil
                continuation.resume(throwing: error)
            } else {
                pendingError = error
            }
        }
    }

    private func deliver(
        _ callback: GoogleOAuthCallback,
        to continuation: CheckedContinuation<GoogleOAuthCallback, Error>
    ) {
        guard callback.state == expectedState else {
            continuation.resume(throwing: GoogleDesktopOAuthError.stateMismatch)
            return
        }

        continuation.resume(returning: callback)
    }

    private func resumeReady(with result: Result<URL, Error>) {
        guard let readyContinuation else { return }
        self.readyContinuation = nil

        switch result {
        case .success(let url):
            readyContinuation.resume(returning: url)
        case .failure(let error):
            readyContinuation.resume(throwing: error)
        }
    }

    private func respond(to connection: NWConnection, success: Bool) {
        let title = success ? "Google authorization received" : "Google authorization failed"
        let message = success
            ? "You can close this window and return to Household Command Center."
            : "Return to Household Command Center and try connecting again."
        let html = """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body style="font: 16px -apple-system, BlinkMacSystemFont, sans-serif; margin: 48px;">
        <h1>\(title)</h1><p>\(message)</p>
        </body></html>
        """
        let body = Data(html.utf8)
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private extension Result {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}
