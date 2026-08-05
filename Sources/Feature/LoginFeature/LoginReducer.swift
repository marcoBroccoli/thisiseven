import AuthClient
import ComposableArchitecture
import EvenCore

@Reducer
public struct LoginReducer {
    @ObservableState
    public struct State: Equatable {
        public var error: String?
        public var working = false
        public init() {}
    }

    public enum Action: ViewAction {
        case view(View)
        case signInSucceeded(AuthBootstrapResult)
        case signInFailed(String)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appleCompleted(identityToken: String, rawNonce: String?)
            case authorizationFailed(String)
            case debugEmailSignIn(email: String, password: String)
            case debugEmailSignUp(email: String, password: String)
        }

        @CasePathable
        public enum Delegate: Equatable {
            /// Signed in, but still needs create/join → App shows Onboarding.
            case needsHousehold
            /// Already in a household → App shows Today.
            case alreadyReady
        }
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(.appleCompleted(token, nonce)):
                state.working = true
                state.error = nil
                return .run { [authClient] send in
                    do {
                        try await send(.signInSucceeded(await authClient.signInWithApple(token, nonce)))
                    } catch {
                        await send(.signInFailed(String(describing: error)))
                    }
                }

            case let .view(.authorizationFailed(message)):
                state.working = false
                state.error = message
                return .none

            case let .view(.debugEmailSignIn(email, password)):
                state.working = true
                state.error = nil
                return .run { [authClient] send in
                    do {
                        try await send(.signInSucceeded(await authClient.signInEmail(email, password)))
                    } catch {
                        await send(.signInFailed(String(describing: error)))
                    }
                }

            case let .view(.debugEmailSignUp(email, password)):
                state.working = true
                state.error = nil
                return .run { [authClient] send in
                    do {
                        try await send(.signInSucceeded(await authClient.signUpEmail(email, password)))
                    } catch {
                        await send(.signInFailed(String(describing: error)))
                    }
                }

            case let .signInSucceeded(result):
                state.working = false
                switch result {
                case .ready:
                    return .send(.delegate(.alreadyReady))
                case .needsHousehold, .signedOut:
                    return .send(.delegate(.needsHousehold))
                }

            case let .signInFailed(message):
                state.working = false
                state.error = message
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
