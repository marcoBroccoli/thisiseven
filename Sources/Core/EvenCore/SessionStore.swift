import Foundation
import Observation

// MARK: - Session persistence

public protocol SessionStorage: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

/// Keychain-backed storage (kilo pattern: one generic-password item).
public struct KeychainSessionStorage: SessionStorage {
    private let store = KeychainDataStore(service: "com.umurburhanyavuz.even.session", account: "gotrue")

    public init() {}

    public func load() -> AuthSession? {
        guard let data = try? store.load() else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? store.save(data)
    }

    public func clear() {
        try? store.clear()
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
    public private(set) lazy var api: EvenAPIClient = .init(
        environment: auth.environment,
        tokenProvider: { [weak self] in try await self?.validAccessToken() }
    )

    public init(environment: APIEnvironment = .current,
                storage: SessionStorage = KeychainSessionStorage())
    {
        auth = AuthService(environment: environment)
        self.storage = storage
    }

    // MARK: Boot

    public func bootstrap() async {
        #if DEBUG
            // UI-test hook: start signed out so E2E runs are repeatable.
            if CommandLine.arguments.contains("--reset-session") {
                storage.clear()
            }
        #endif
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
            if case let APIError.http(status, _, _) = error, status == 401 {
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
        try adopt(await auth.signInWithApple(identityToken: identityToken, rawNonce: rawNonce))
        await refreshIdentity()
    }

    public func signIn(email: String, password: String) async throws {
        try adopt(await auth.signIn(email: email, password: password))
        await refreshIdentity()
    }

    public func signUp(email: String, password: String) async throws {
        try adopt(await auth.signUp(email: email, password: password))
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

    /// Fresh `/v1/me` for Profile (also refreshes in-memory identity).
    public func loadProfile() async throws -> MeResponse {
        let me = try await api.me()
        self.me = me
        if me.household != nil {
            phase = .ready
        }
        return me
    }

    public func updateMe(displayName: String?, color: MemberColor?) async throws -> Member {
        let member = try await api.patchMe(displayName: displayName, color: color)
        await refreshIdentity()
        return member
    }

    public func uploadAvatar(jpeg: Data) async throws -> Member {
        let member = try await api.putMyAvatar(jpeg: jpeg)
        await MemberAvatarCache.shared.store(member.id, data: jpeg)
        await refreshIdentity()
        return member
    }

    public func deleteAvatar() async throws -> Member {
        let member = try await api.deleteMyAvatar()
        await MemberAvatarCache.shared.remove(member.id)
        await refreshIdentity()
        return member
    }

    public func fetchAvatar(memberId: UUID) async throws -> Data {
        if let cached = await MemberAvatarCache.shared.data(for: memberId) {
            return cached
        }
        let data = try await api.memberAvatarData(memberId: memberId)
        await MemberAvatarCache.shared.store(memberId, data: data)
        return data
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
