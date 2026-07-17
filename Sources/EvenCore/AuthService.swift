import Foundation

/// A GoTrue session as returned by /auth/token and /auth/signup.
public struct AuthSession: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public var isFresh: Bool { expiresAt.timeIntervalSinceNow > 60 }
}

struct GoTrueTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double

    var session: AuthSession {
        AuthSession(accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: Date().addingTimeInterval(expiresIn))
    }
}

public enum AuthError: Error, LocalizedError {
    case server(String)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case let .server(message): return message
        case .transport: return "Can't reach the house server."
        }
    }
}

/// Minimal GoTrue client speaking the standard Supabase auth API through
/// evend's /auth/* proxy — identical shape to a Supabase cloud project, so
/// a later cloud move is a base-URL swap.
public struct AuthService: Sendable {
    public let environment: APIEnvironment
    private let session: URLSession

    public init(environment: APIEnvironment = .current, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    public func signInWithApple(identityToken: String, rawNonce: String?) async throws -> AuthSession {
        var body: [String: String] = ["provider": "apple", "id_token": identityToken]
        if let rawNonce { body["nonce"] = rawNonce }
        return try await token(grantType: "id_token", body: body)
    }

    public func signIn(email: String, password: String) async throws -> AuthSession {
        try await token(grantType: "password", body: ["email": email, "password": password])
    }

    public func signUp(email: String, password: String) async throws -> AuthSession {
        // With GOTRUE_MAILER_AUTOCONFIRM the signup response contains a session.
        try await request(path: "auth/signup", query: nil,
                          body: ["email": email, "password": password])
    }

    public func refresh(_ current: AuthSession) async throws -> AuthSession {
        try await token(grantType: "refresh_token",
                        body: ["refresh_token": current.refreshToken])
    }

    public func signOut(accessToken: String) async {
        var req = URLRequest(url: environment.baseURL.appendingPathComponent("auth/logout"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: req)
    }

    private func token(grantType: String, body: [String: String]) async throws -> AuthSession {
        try await request(path: "auth/token", query: "grant_type=\(grantType)", body: body)
    }

    private func request(path: String, query: String?, body: [String: String]) async throws -> AuthSession {
        var components = URLComponents(url: environment.baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        components.query = query
        var req = URLRequest(url: components.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AuthError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(status) else {
            // GoTrue error bodies vary: {error, error_description} or {msg} or {message}.
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = (obj["error_description"] ?? obj["msg"] ?? obj["message"] ?? obj["error"])
                    as? String
                throw AuthError.server(message ?? "Sign-in failed (\(status)).")
            }
            throw AuthError.server("Sign-in failed (\(status)).")
        }
        do {
            return try decoder.decode(GoTrueTokenResponse.self, from: data).session
        } catch {
            throw AuthError.server("Unexpected sign-in reply.")
        }
    }
}
