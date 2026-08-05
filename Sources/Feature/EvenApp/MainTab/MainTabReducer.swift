import ComposableArchitecture
import InboxFeature
import TodayFeature

@Reducer
public struct MainTabReducer {
    @ObservableState
    public struct State: Equatable {
        public var inbox = InboxReducer.State()
        public var today = TodayReducer.State()
        public var tab: Tab = .today
        public init() {}

        public enum Tab: Equatable, Sendable {
            case inbox, today
        }
    }

    public enum Action: ViewAction {
        case view(View)
        case inbox(InboxReducer.Action)
        case today(TodayReducer.Action)

        @CasePathable
        public enum View: Equatable, Sendable {
            case selectTab(State.Tab)
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.inbox, action: \.inbox) { InboxReducer() }
        Scope(state: \.today, action: \.today) { TodayReducer() }
        Reduce { state, action in
            switch action {
            case let .view(.selectTab(tab)):
                state.tab = tab
                return .none
            case .inbox, .today:
                return .none
            }
        }
    }
}
