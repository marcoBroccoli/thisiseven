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

    /// Canvas default — Ada/Umut household; sign-in lands on household setup.
    public static let previewValue = AuthClient(
        bootstrap: { .signedOut },
        signInWithApple: { _, _ in .needsHousehold(userId: PreviewData.adaId) },
        signInEmail: { _, _ in .needsHousehold(userId: PreviewData.adaId) },
        signUpEmail: { _, _ in .needsHousehold(userId: PreviewData.adaId) },
        signOut: {},
        refreshIdentity: { .signedOut },
        householdMembers: { (PreviewData.ada, PreviewData.umut) }
    )
}

public extension DependencyValues {
    var authClient: AuthClient {
        get { self[AuthClient.self] }
        set { self[AuthClient.self] = newValue }
    }
}
