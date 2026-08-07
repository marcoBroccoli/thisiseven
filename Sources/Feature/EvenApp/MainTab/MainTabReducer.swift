import ComposableArchitecture
import Foundation
import HouseholdRealtimeClient
import InboxFeature
import ProfileFeature
import TodayFeature

@Reducer
public struct MainTabReducer {
    @ObservableState
    public struct State: Equatable {
        public var inbox = InboxReducer.State()
        public var today = TodayReducer.State()
        public var profile = ProfileReducer.State()
        public var tab: Tab = .today
        public init() {}

        public enum Tab: String, CaseIterable, Equatable, Sendable {
            case today
            case inbox
            case profile
        }
    }

    public enum Action: ViewAction {
        case view(View)
        case inbox(InboxReducer.Action)
        case today(TodayReducer.Action)
        case profile(ProfileReducer.Action)
        case realtime(HouseholdRealtimeEvent)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case selectTab(State.Tab)
        }

        @CasePathable
        public enum Delegate: Equatable {
            case signedOut
        }
    }

    private enum CancelID { case householdRealtime }

    @Dependency(\.householdRealtimeClient) var householdRealtimeClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.inbox, action: \.inbox) { InboxReducer() }
        Scope(state: \.today, action: \.today) { TodayReducer() }
        Scope(state: \.profile, action: \.profile) { ProfileReducer() }
        Reduce { state, action in
            switch action {
            case .view(.appear):
                return .run { [householdRealtimeClient] send in
                    for await event in householdRealtimeClient.events() {
                        await send(.realtime(event))
                    }
                }
                .cancellable(id: CancelID.householdRealtime, cancelInFlight: true)

            case let .view(.selectTab(tab)):
                state.tab = tab
                return .none

            case let .realtime(event):
                guard event.invalidatesSummary else { return .none }
                // Own taps already mutated Today optimistically — skip a second
                // refetch/beam animation when the actor is me.
                if let actor = event.actorMemberId, actor == state.today.me?.id {
                    return .none
                }
                return .send(.today(.view(.refresh)))

            case .profile(.delegate(.signedOut)):
                return .send(.delegate(.signedOut))

            case .delegate:
                return .none

            case .inbox, .today, .profile:
                return .none
            }
        }
    }
}
