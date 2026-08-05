import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

public enum AuthBootstrapResult: Equatable, Sendable {
    case signedOut
    case needsHousehold(userId: UUID)
    case ready
}

@DependencyClient
public struct AuthClient: Sendable {
    public var bootstrap: @Sendable () async -> AuthBootstrapResult = { .signedOut }
    public var signInWithApple: @Sendable (_ identityToken: String, _ rawNonce: String?) async throws -> AuthBootstrapResult = { _, _ in
        .signedOut
    }

    public var signInEmail: @Sendable (_ email: String, _ password: String) async throws -> AuthBootstrapResult = { _, _ in
        .signedOut
    }

    public var signUpEmail: @Sendable (_ email: String, _ password: String) async throws -> AuthBootstrapResult = { _, _ in
        .signedOut
    }

    public var signOut: @Sendable () async -> Void = {}
    public var refreshIdentity: @Sendable () async -> AuthBootstrapResult = { .signedOut }
    public var householdMembers: @Sendable () async -> (me: Member?, partner: Member?) = { (nil, nil) }
}

extension AuthClient: TestDependencyKey {
    public static let testValue = AuthClient()
}

public extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}
