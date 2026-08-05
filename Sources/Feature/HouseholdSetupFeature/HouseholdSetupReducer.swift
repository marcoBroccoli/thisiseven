import ComposableArchitecture
import Design
import EvenCore
import HouseholdClient

@Reducer
public struct HouseholdSetupReducer {
    @ObservableState
    public struct State: Equatable {
        public var path: Path = .choice
        public var name: String = ""
        public var inviteCode: String = ""
        public var displayName: String = ""
        public var inviteReveal: String?
        public var error: String?
        public var working = false
        public init() {}
    }

    public enum Path: Equatable, Sendable {
        case choice, create, inviteReveal, join, waiting
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)
        case createSucceeded(Household)
        case createFailed(String)
        case joinSucceeded(Household)
        case joinFailed(String)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case createTapped
            case joinTapped
            case submitCreate
            case submitJoin
            case continueAfterInvite
        }

        public enum Delegate: Equatable {
            case finished
        }
    }

    @Dependency(\.householdClient) var householdClient

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case .view(.createTapped):
                state.path = .create
                state.error = nil
                return .none
            case .view(.joinTapped):
                state.path = .join
                state.error = nil
                return .none
            case .view(.submitCreate):
                state.working = true
                let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = state.displayName.isEmpty ? "Me" : state.displayName
                return .run { [householdClient] send in
                    do {
                        try await send(.createSucceeded(await householdClient.create(name, display)))
                    } catch {
                        await send(.createFailed(String(describing: error)))
                    }
                }
            case .view(.submitJoin):
                state.working = true
                let code = state.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = state.displayName.isEmpty ? "Me" : state.displayName
                return .run { [householdClient] send in
                    do {
                        try await send(.joinSucceeded(await householdClient.join(code, display)))
                    } catch {
                        await send(.joinFailed(String(describing: error)))
                    }
                }
            case let .createSucceeded(household):
                state.working = false
                state.inviteReveal = household.inviteCode
                state.path = .inviteReveal
                return .none
            case .joinSucceeded:
                state.working = false
                state.path = .waiting
                return .send(.delegate(.finished))
            case let .createFailed(message), let .joinFailed(message):
                state.working = false
                state.error = message
                return .none
            case .view(.continueAfterInvite):
                return .send(.delegate(.finished))
            case .delegate:
                return .none
            }
        }
    }
}
