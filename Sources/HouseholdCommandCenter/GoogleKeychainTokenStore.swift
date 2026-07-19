import Foundation
import HouseholdCore
import Security

struct StoredGoogleTokens: Codable, Equatable, Sendable {
    var clientID: String
    var clientSecret: String?
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountHint: String
    var grantedScopes: [String]

    init(
        clientID: String,
        clientSecret: String?,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        accountHint: String,
        grantedScopes: [String]
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountHint = accountHint
        self.grantedScopes = grantedScopes
    }

    private enum CodingKeys: String, CodingKey {
        case clientID
        case clientSecret
        case accessToken
        case refreshToken
        case expiresAt
        case accountHint
        case grantedScopes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try container.decode(String.self, forKey: .clientID)
        clientSecret = try container.decodeIfPresent(String.self, forKey: .clientSecret)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        accountHint = try container.decode(String.self, forKey: .accountHint)
        grantedScopes = try container.decodeIfPresent([String].self, forKey: .grantedScopes) ?? []
    }
}

enum GoogleKeychainTokenStoreError: Error, LocalizedError {
    case encodeFailed
    case decodeFailed
    case keychainStatus(OSStatus)
    case missingStoredTokens
    case tokenRefreshFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            "Could not encode Google tokens for Keychain."
        case .decodeFailed:
            "Could not decode Google tokens from Keychain."
        case .keychainStatus(let status):
            "Keychain operation failed with status \(status)."
        case .missingStoredTokens:
            "Google is not connected yet."
        case .tokenRefreshFailed(let status, let message):
            "Google token refresh failed with HTTP \(status): \(message)"
        }
    }
}

final class GoogleKeychainTokenStore: @unchecked Sendable {
    private let service = "HouseholdCommandCenter.GoogleOAuth"
    private let account = "google-oauth-tokens"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() throws -> StoredGoogleTokens? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw GoogleKeychainTokenStoreError.keychainStatus(status)
        }

        guard let data = item as? Data else {
            throw GoogleKeychainTokenStoreError.decodeFailed
        }

        do {
            return try decoder.decode(StoredGoogleTokens.self, from: data)
        } catch {
            throw GoogleKeychainTokenStoreError.decodeFailed
        }
    }

    func save(_ tokens: StoredGoogleTokens) throws {
        guard let data = try? encoder.encode(tokens) else {
            throw GoogleKeychainTokenStoreError.encodeFailed
        }

        var query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw GoogleKeychainTokenStoreError.keychainStatus(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw GoogleKeychainTokenStoreError.keychainStatus(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleKeychainTokenStoreError.keychainStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class GoogleKeychainAccessTokenProvider: GoogleAccessTokenProvider, @unchecked Sendable {
    private let clientID: String
    private let clientSecret: String?
    private let tokenStore: GoogleKeychainTokenStore
    private let transport: GoogleHTTPTransport
    private let decoder = JSONDecoder()

    init(
        clientID: String,
        clientSecret: String? = nil,
        tokenStore: GoogleKeychainTokenStore,
        transport: GoogleHTTPTransport = URLSessionGoogleHTTPTransport()
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret?.nilIfBlank
        self.tokenStore = tokenStore
        self.transport = transport
    }

    func accessToken() async throws -> String {
        guard var tokens = try tokenStore.load() else {
            throw GoogleKeychainTokenStoreError.missingStoredTokens
        }

        if tokens.expiresAt > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }

        let request = try GoogleOAuthTokenRequestFactory.refreshTokenRequest(
            clientID: clientID,
            clientSecret: clientSecret ?? tokens.clientSecret,
            refreshToken: tokens.refreshToken
        )
        let response: GoogleOAuthTokenResponse = try await perform(request)

        tokens.accessToken = response.accessToken
        tokens.refreshToken = response.refreshToken ?? tokens.refreshToken
        tokens.expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        try tokenStore.save(tokens)

        return tokens.accessToken
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleKeychainTokenStoreError.tokenRefreshFailed(
                response.statusCode,
                GoogleOAuthTokenErrorFormatter.message(from: data)
            )
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private enum GoogleOAuthTokenErrorFormatter {
    static func message(from data: Data) -> String {
        guard let payload = try? JSONDecoder().decode(GoogleOAuthTokenErrorPayload.self, from: data) else {
            return String(data: data, encoding: .utf8) ?? "No response body."
        }

        if let description = payload.errorDescription, !description.isEmpty {
            return "\(payload.error): \(description)"
        }
        return payload.error
    }
}

private struct GoogleOAuthTokenErrorPayload: Decodable {
    var error: String
    var errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
