import ComposableArchitecture

/// How-it-works after login when the user still needs a household.
/// State is an enum — one case per page (TCA enum-state pattern).
@Reducer
public struct OnboardingReducer {
    @ObservableState
    public enum State: Equatable, Sendable {
        case weigh
        case drafts
        case sunday

        public var showsBack: Bool {
            self != .weigh
        }

        public var isLast: Bool {
            self == .sunday
        }

        public var pageIndex: Int {
            switch self {
            case .weigh: 0
            case .drafts: 1
            case .sunday: 2
            }
        }

        public static let allCases: [State] = [.weigh, .drafts, .sunday]

        fileprivate var next: State? {
            switch self {
            case .weigh: .drafts
            case .drafts: .sunday
            case .sunday: nil
            }
        }

        fileprivate var previous: State? {
            switch self {
            case .weigh: nil
            case .drafts: .weigh
            case .sunday: .drafts
            }
        }

        public var title: String {
            switch self {
            case .weigh: "Work you can weigh."
            case .drafts: "Drafts, not demands."
            case .sunday: "Sunday, pour the pans."
            }
        }

        public var message: String {
            switch self {
            case .weigh:
                "Every finished task drops a pebble in your pan — heavier chores, heavier pebbles. The beam shows the week's balance at a glance, so nobody has to keep score out loud."
            case .drafts:
                "Bills and appointments in your Gmail become drafts in a shared inbox. A draft turns into a task or calendar event only after your partner has looked at it and approved."
            case .sunday:
                "Once a week, ten minutes together: look at the balance honestly, say one kind thing each, trade what isn't working. Then the pans empty and Monday starts level."
            }
        }
    }

    public enum Action: ViewAction {
        case view(View)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case nextTapped
            case backTapped
            case skipTapped
        }

        @CasePathable
        public enum Delegate: Equatable {
            case finished
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.nextTapped):
                if let next = state.next {
                    state = next
                    return .none
                }
                return .send(.delegate(.finished))

            case .view(.backTapped):
                if let previous = state.previous {
                    state = previous
                }
                return .none

            case .view(.skipTapped):
                return .send(.delegate(.finished))

            case .delegate:
                return .none
            }
        }
    }
}
