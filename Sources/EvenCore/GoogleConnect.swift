import Foundation
import CryptoKit

/// In-app Google connect: the app runs the consent in ASWebAuthenticationSession
/// against the iOS OAuth client (PKCE, no secret) and hands the code to evend,
/// which exchanges + stores the refresh token per household. Any number of
/// users can connect concurrently — all state below is per-attempt.
public enum GoogleConnectConfig {
    /// iOS OAuth client (GCP project workspace-cli-umur, client "Even iOS").
    /// Empty string hides the connect feature entirely.
    public static let iosClientID =
        "733777745150-gb5i361it6sghbc48qlgil58nsojniq7.apps.googleusercontent.com"

    public static var isEnabled: Bool { !iosClientID.isEmpty }

    /// Reversed-client-id custom scheme, e.g. com.googleusercontent.apps.NNN-xxx
    public static var redirectScheme: String {
        iosClientID.split(separator: ".").reversed().joined(separator: ".")
    }

    public static var redirectURI: String { redirectScheme + ":/oauth2redirect" }
}

/// One consent attempt: fresh PKCE verifier + state.
public struct GoogleConnectAttempt: Sendable {
    public let codeVerifier: String
    public let state: String
    public let authorizationURL: URL

    public init() {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        codeVerifier = String((0..<64).map { _ in charset.randomElement()! })
        state = UUID().uuidString

        let challenge = Data(SHA256.hash(data: Data(codeVerifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: GoogleConnectConfig.iosClientID),
            .init(name: "redirect_uri", value: GoogleConnectConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.events openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        authorizationURL = components.url!
    }

    /// Extracts the authorization code from the callback URL, checking state.
    public func code(from callback: URL) -> String? {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == state else { return nil }
        return items.first(where: { $0.name == "code" })?.value
    }
}

public extension EvenAPIClient {
    /// Hands the consent code to evend, which exchanges and stores it.
    func googleConnect(code: String, codeVerifier: String) async throws -> GoogleStatus {
        struct B: Encodable {
            let code: String
            let redirectUri: String
            let codeVerifier: String
        }
        return try await post("v1/google/connect", B(
            code: code,
            redirectUri: GoogleConnectConfig.redirectURI,
            codeVerifier: codeVerifier))
    }
}
