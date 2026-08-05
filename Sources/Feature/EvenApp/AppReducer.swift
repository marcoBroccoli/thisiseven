import AuthClient
import ComposableArchitecture
import ConnectionsFeature
import Foundation
import HouseholdSetupFeature
import InboxFeature
import LoginFeature
import OnboardingFeature
import TodayFeature

@Reducer
public struct AppReducer {
    @ObservableState
    public enum State: Equatable {
        case booting
        case login(LoginReducer.State)
        case onboarding(OnboardingReducer.State)
        case householdSetup(HouseholdSetupReducer.State)
        case connections(ConnectionsReducer.State)
        case ready(MainTabReducer.State)
    }

    public enum Action: ViewAction {
        case view(View)
        case bootstrapResponse(AuthBootstrapResult)
        case login(LoginReducer.Action)
        case onboarding(OnboardingReducer.Action)
        case householdSetup(HouseholdSetupReducer.Action)
        case connections(ConnectionsReducer.Action)
        case ready(MainTabReducer.Action)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appStarted
        }
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appStarted):
                return .run { [authClient] send in
                    await send(.bootstrapResponse(await authClient.bootstrap()))
                }

            case let .bootstrapResponse(result):
                switch result {
                case .signedOut:
                    state = .login(LoginReducer.State())
                case .needsHousehold:
                    // Already signed in, past login — skip how-it-works.
                    state = .householdSetup(HouseholdSetupReducer.State())
                case .ready:
                    state = .ready(MainTabReducer.State())
                }
                return .none

            case .login(.delegate(.needsHousehold)):
                state = .onboarding(.weigh)
                return .none

            case .login(.delegate(.alreadyReady)):
                state = .ready(MainTabReducer.State())
                return .none

            case .onboarding(.delegate(.finished)):
                state = .householdSetup(HouseholdSetupReducer.State())
                return .none

            case .householdSetup(.delegate(.finished)):
                state = .connections(ConnectionsReducer.State())
                return .none

            case .connections(.delegate(.finished)):
                state = .ready(MainTabReducer.State())
                return .none

            case .login, .onboarding, .householdSetup, .connections, .ready:
                return .none
            }
        }
        .ifCaseLet(\.login, action: \.login) { LoginReducer() }
        .ifCaseLet(\.onboarding, action: \.onboarding) { OnboardingReducer() }
        .ifCaseLet(\.householdSetup, action: \.householdSetup) { HouseholdSetupReducer() }
        .ifCaseLet(\.connections, action: \.connections) { ConnectionsReducer() }
        .ifCaseLet(\.ready, action: \.ready) { MainTabReducer() }
    }
}
