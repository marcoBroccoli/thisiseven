import ComposableArchitecture

@Reducer
public struct ComposerReducer {
    @ObservableState
    public struct State: Equatable {
        public var title = ""
        public var weight = 2
        public var ownerIsMe = true
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)

        @CasePathable
        public enum View: Equatable, Sendable {
            case saveTapped
            case cancelTapped
            case selectWeight(Int)
            case selectOwner(Bool)
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .view(.selectWeight(w)):
                state.weight = w
                return .none
            case let .view(.selectOwner(me)):
                state.ownerIsMe = me
                return .none
            case .binding, .view(.saveTapped), .view(.cancelTapped):
                return .none
            }
        }
    }
}
