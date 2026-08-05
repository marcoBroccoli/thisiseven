import AuthClient
import Dependencies
import EvenCore
import Foundation

extension AuthClient: DependencyKey {
    public static let liveValue = AuthClient(
        bootstrap: {
            let store = await MainActor.run { SharedSession.store }
            await store.bootstrap()
            return await MainActor.run { mapPhase(SharedSession.store.phase) }
        },
        signInWithApple: { token, nonce in
            let store = await MainActor.run { SharedSession.store }
            try await store.signInWithApple(identityToken: token, rawNonce: nonce)
            return await MainActor.run { mapPhase(SharedSession.store.phase) }
        },
        signInEmail: { email, password in
            let store = await MainActor.run { SharedSession.store }
            try await store.signIn(email: email, password: password)
            return await MainActor.run { mapPhase(SharedSession.store.phase) }
        },
        signUpEmail: { email, password in
            let store = await MainActor.run { SharedSession.store }
            try await store.signUp(email: email, password: password)
            return await MainActor.run { mapPhase(SharedSession.store.phase) }
        },
        signOut: {
            let store = await MainActor.run { SharedSession.store }
            await store.signOut()
        },
        refreshIdentity: {
            let store = await MainActor.run { SharedSession.store }
            await store.refreshIdentity()
            return await MainActor.run { mapPhase(SharedSession.store.phase) }
        },
        householdMembers: {
            await MainActor.run {
                let household = SharedSession.store.me?.household
                return (household?.me, household?.partner)
            }
        }
    )
}

private func mapPhase(_ phase: SessionPhase) -> AuthBootstrapResult {
    switch phase {
    case .booting, .signedOut:
        return .signedOut
    case let .needsHousehold(userId):
        return .needsHousehold(userId: userId)
    case .ready:
        return .ready
    }
}
