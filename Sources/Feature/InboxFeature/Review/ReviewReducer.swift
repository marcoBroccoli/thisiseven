import ComposableArchitecture
import EvenCore
import Foundation

@Reducer
public struct ReviewReducer {
    @ObservableState
    public struct State: Equatable, Identifiable {
        public var id: UUID {
            draft.id
        }

        public var draft: Draft
        public var title: String
        public var ownerMemberId: UUID
        public var reminder: DraftReminder
        public var me: Member?
        public var partner: Member?

        public init(draft: Draft, me: Member?, partner: Member?) {
            self.draft = draft
            title = draft.title
            ownerMemberId = draft.ownerMemberId
            reminder = draft.reminder
            self.me = me
            self.partner = partner
        }
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)

        @CasePathable
        public enum View: Equatable, Sendable {
            case selectOwner(UUID)
            case selectReminder(DraftReminder)
            case approveTapped
            case dismissTapped
            case closeTapped
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .view(.selectOwner(id)):
                state.ownerMemberId = id
                return .none
            case let .view(.selectReminder(reminder)):
                state.reminder = reminder
                return .none
            case .binding, .view(.approveTapped), .view(.dismissTapped), .view(.closeTapped):
                return .none
            }
        }
    }
}
