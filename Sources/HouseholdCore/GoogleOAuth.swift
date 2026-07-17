import Foundation
import CryptoKit

public enum GoogleOAuthScope: String, CaseIterable, Sendable {
    case gmailReadonly = "https://www.googleapis.com/auth/gmail.readonly"
    case gmailCompose = "https://www.googleapis.com/auth/gmail.compose"
    case calendarEvents = "https://www.googleapis.com/auth/calendar.events"
    case openid
    case email
    case profile
}

public struct GoogleOAuthConfiguration: Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String?
    public var redirectURI: String
    public var scopes: [GoogleOAuthScope]

    public init(clientID: String, clientSecret: String? = nil, redirectURI: String, scopes: [GoogleOAuthScope]) {
        self.clientID = clientID
        self.clientSecret = clientSecret?.nilIfBlank
        self.redirectURI = redirectURI
        self.scopes = scopes
    }
}

public enum GoogleOAuthRequestError: Error, Equatable {
    case invalidAuthorizationURL
}

public enum GoogleOAuthRedirectURI {
    public static func loopback(port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }
}

public enum GoogleOAuthRequestFactory {
    public static func authorizationURL(
        configuration: GoogleOAuthConfiguration,
        state: String,
        codeChallenge: String
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "accounts.google.com"
        components.path = "/o/oauth2/v2/auth"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.map(\.rawValue).joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components.url else {
            throw GoogleOAuthRequestError.invalidAuthorizationURL
        }

        return url
    }
}

public enum GoogleOAuthPKCE {
    private static let verifierCharacters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    public static func randomVerifier(length: Int = 64) -> String {
        precondition((43...128).contains(length), "PKCE verifier length must be between 43 and 128 characters.")

        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in verifierCharacters.randomElement(using: &generator)! })
    }

    public static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

public struct GoogleOAuthTokenResponse: Equatable, Codable, Sendable {
    public var accessToken: String
    public var expiresIn: Int
    public var refreshToken: String?
    public var scope: String?
    public var tokenType: String
    public var idToken: String?

    public init(
        accessToken: String,
        expiresIn: Int,
        refreshToken: String?,
        scope: String?,
        tokenType: String,
        idToken: String?
    ) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.tokenType = tokenType
        self.idToken = idToken
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
        case idToken = "id_token"
    }
}

public enum GoogleOAuthTokenRequestFactory {
    public static func authorizationCodeRequest(
        configuration: GoogleOAuthConfiguration,
        code: String,
        codeVerifier: String
    ) throws -> URLRequest {
        var parameters = [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI
        ]

        if let clientSecret = configuration.clientSecret {
            parameters["client_secret"] = clientSecret
        }

        return try tokenRequest(parameters: parameters)
    }

    public static func refreshTokenRequest(
        clientID: String,
        clientSecret: String? = nil,
        refreshToken: String
    ) throws -> URLRequest {
        var parameters = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]

        if let clientSecret = clientSecret?.nilIfBlank {
            parameters["client_secret"] = clientSecret
        }

        return try tokenRequest(parameters: parameters)
    }

    private static func tokenRequest(parameters: [String: String]) throws -> URLRequest {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleOAuthRequestError.invalidAuthorizationURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(parameters)
        return request
    }

    private static func formBody(_ parameters: [String: String]) -> Data {
        parameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key.formURLEncoded())=\($0.value.formURLEncoded())" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func formURLEncoded() -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
