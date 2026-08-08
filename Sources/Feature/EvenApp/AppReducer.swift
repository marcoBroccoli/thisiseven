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
        case booting(BootingState = BootingState())
        case login(LoginReducer.State)
        case onboarding(OnboardingReducer.State)
        case householdSetup(HouseholdSetupReducer.State)
        case connections(ConnectionsReducer.State)
        case ready(MainTabReducer.State)
    }

    public struct BootingState: Equatable, Sendable {
        public var bootstrapResult: AuthBootstrapResult?
        public var splashFinished: Bool

        public init(
            bootstrapResult: AuthBootstrapResult? = nil,
            splashFinished: Bool = false
        ) {
            self.bootstrapResult = bootstrapResult
            self.splashFinished = splashFinished
        }
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
            case splashFinished
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

            case .view(.splashFinished):
                guard case var .booting(boot) = state else { return .none }
                boot.splashFinished = true
                return applyBootIfReady(&state, boot: boot)

            case let .bootstrapResponse(result):
                guard case var .booting(boot) = state else { return .none }
                boot.bootstrapResult = result
                return applyBootIfReady(&state, boot: boot)

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

            case .ready(.delegate(.signedOut)):
                state = .login(LoginReducer.State())
                return .none

            case .ready(.delegate(.leftLastHousehold)):
                // Still signed in, just homeless — straight back to the
                // join-or-create door, not through how-it-works.
                state = .householdSetup(HouseholdSetupReducer.State())
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

    /// Leave splash only after bootstrap *and* the glyph/wordmark beat finish.
    private func applyBootIfReady(
        _ state: inout State,
        boot: BootingState
    ) -> Effect<Action> {
        guard boot.splashFinished, let result = boot.bootstrapResult else {
            state = .booting(boot)
            return .none
        }
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
    }
}
