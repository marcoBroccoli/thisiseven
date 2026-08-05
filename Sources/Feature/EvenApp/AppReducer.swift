import AuthClient
import ComposableArchitecture
import ConnectionsFeature
import Foundation
import HouseholdSetupFeature
import InboxFeature
import OnboardingFeature
import TodayFeature

@Reducer
public struct MainReducer {
    @ObservableState
    public struct State: Equatable {
        public var inbox = InboxFeature.State()
        public var today = TodayFeature.State()
        public var tab: Tab = .today
        public init() {}

        public enum Tab: Equatable, Sendable {
            case inbox, today
        }
    }

    public enum Action {
        case inbox(InboxFeature.Action)
        case today(TodayFeature.Action)
        case selectTab(State.Tab)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.inbox, action: \.inbox) { InboxFeature() }
        Scope(state: \.today, action: \.today) { TodayFeature() }
        Reduce { state, action in
            switch action {
            case let .selectTab(tab):
                state.tab = tab
                return .none
            case .inbox, .today:
                return .none
            }
        }
    }
}

@Reducer
public struct AppReducer {
    @ObservableState
    public enum State: Equatable {
        case booting
        case onboarding(OnboardingFeature.State)
        case householdSetup(HouseholdSetupFeature.State)
        case connections(ConnectionsFeature.State)
        case ready(MainReducer.State)
    }

    public enum Action {
        case appStarted
        case bootstrapResponse(AuthBootstrapResult)
        case onboarding(OnboardingFeature.Action)
        case householdSetup(HouseholdSetupFeature.Action)
        case connections(ConnectionsFeature.Action)
        case ready(MainReducer.Action)
    }

    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appStarted:
                return .run { [authClient] send in
                    await send(.bootstrapResponse(await authClient.bootstrap()))
                }

            case let .bootstrapResponse(result):
                switch result {
                case .signedOut:
                    state = .onboarding(OnboardingFeature.State())
                case .needsHousehold:
                    state = .householdSetup(HouseholdSetupFeature.State())
                case .ready:
                    state = .ready(MainReducer.State())
                }
                return .none

            case .onboarding(.delegate(.needsHousehold)):
                state = .householdSetup(HouseholdSetupFeature.State())
                return .none

            case .onboarding(.delegate(.alreadyReady)):
                state = .ready(MainReducer.State())
                return .none

            case .householdSetup(.delegate(.finished)):
                state = .connections(ConnectionsFeature.State())
                return .none

            case .connections(.delegate(.finished)):
                state = .ready(MainReducer.State())
                return .none

            case .onboarding, .householdSetup, .connections, .ready:
                return .none
            }
        }
        .ifCaseLet(\.onboarding, action: \.onboarding) { OnboardingFeature() }
        .ifCaseLet(\.householdSetup, action: \.householdSetup) { HouseholdSetupFeature() }
        .ifCaseLet(\.connections, action: \.connections) { ConnectionsFeature() }
        .ifCaseLet(\.ready, action: \.ready) { MainReducer() }
    }
}
