import Foundation
import Observation
import Security

// MARK: - Session persistence

public protocol SessionStorage: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

/// Keychain-backed storage (kilo pattern: one generic-password item).
public struct KeychainSessionStorage: SessionStorage {
    let service = "com.umuryavuz.even.session"

    public init() {}

    public func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        var query = baseQuery
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "gotrue"]
    }
}

// MARK: - Session store

public enum SessionPhase: Equatable, Sendable {
    case booting
    case signedOut
    /// Signed in but no household yet — onboarding continues.
    case needsHousehold(userId: UUID)
    case ready
}

/// App-wide auth + identity state. UI observes `phase`; the API client pulls
/// tokens through `validAccessToken()` which transparently refreshes.
@Observable
public final class SessionStore: @unchecked Sendable {
    public private(set) var phase: SessionPhase = .booting
    public private(set) var me: MeResponse?

    public let auth: AuthService
    private let storage: SessionStorage
    private var session: AuthSession?
    @ObservationIgnored
    public private(set) lazy var api: EvenAPIClient = EvenAPIClient(
        environment: auth.environment,
        tokenProvider: { [weak self] in try await self?.validAccessToken() }
    )

    public init(environment: APIEnvironment = .current,
                storage: SessionStorage = KeychainSessionStorage()) {
        self.auth = AuthService(environment: environment)
        self.storage = storage
    }

    // MARK: Boot

    public func bootstrap() async {
        guard let stored = storage.load() else {
            phase = .signedOut
            return
        }
        session = stored
        await refreshIdentity()
    }

    /// Re-fetches /v1/me and routes the phase. Safe to call any time.
    public func refreshIdentity() async {
        do {
            let me = try await api.me()
            self.me = me
            phase = me.household == nil ? .needsHousehold(userId: me.userId) : .ready
        } catch {
            if case APIError.http(let status, _, _) = error, status == 401 {
                storage.clear()
                session = nil
                phase = .signedOut
            } else if phase == .booting {
                // Server unreachable at boot with a stored session: stay hopeful.
                phase = session == nil ? .signedOut : .ready
            }
        }
    }

    // MARK: Sign-in flows

    public func signInWithApple(identityToken: String, rawNonce: String?) async throws {
        adopt(try await auth.signInWithApple(identityToken: identityToken, rawNonce: rawNonce))
        await refreshIdentity()
    }

    public func signIn(email: String, password: String) async throws {
        adopt(try await auth.signIn(email: email, password: password))
        await refreshIdentity()
    }

    public func signUp(email: String, password: String) async throws {
        adopt(try await auth.signUp(email: email, password: password))
        await refreshIdentity()
    }

    public func signOut() async {
        if let session { await auth.signOut(accessToken: session.accessToken) }
        storage.clear()
        session = nil
        me = nil
        phase = .signedOut
    }

    // MARK: Household onboarding

    public func createHousehold(name: String, displayName: String) async throws {
        _ = try await api.createHousehold(name: name, displayName: displayName)
        await refreshIdentity()
    }

    public func joinHousehold(inviteCode: String, displayName: String) async throws {
        _ = try await api.joinHousehold(inviteCode: inviteCode, displayName: displayName)
        await refreshIdentity()
    }

    // MARK: Tokens

    private func adopt(_ new: AuthSession) {
        session = new
        storage.save(new)
    }

    public func validAccessToken() async throws -> String? {
        guard var current = session else { return nil }
        if !current.isFresh {
            current = try await auth.refresh(current)
            adopt(current)
        }
        return current.accessToken
    }
}
