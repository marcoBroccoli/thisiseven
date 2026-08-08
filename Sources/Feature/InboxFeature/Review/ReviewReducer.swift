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
        /// Editable due date (`YYYY-MM-DD`). Seeded from the draft, which for a
        /// Gmail draft means the extractor found it in the email.
        public var dueOn: String?
        public var me: Member?
        public var partner: Member?

        public init(draft: Draft, me: Member?, partner: Member?) {
            self.draft = draft
            title = draft.title
            ownerMemberId = draft.ownerMemberId
            reminder = draft.reminder
            dueOn = draft.dueOn
            self.me = me
            self.partner = partner
        }

        /// The date the ingest wrote — the only "detected" signal the API carries.
        public var detectedDueOn: String? {
            draft.dueOn
        }

        /// Gmail drafts get `due_on` only from the email extractor; a
        /// partner-created draft got it from a person.
        public var dueOnWasDetected: Bool {
            draft.isFromGmail && draft.dueOn != nil
        }

        public var dueOnEdited: Bool {
            dueOn != draft.dueOn
        }
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)

        @CasePathable
        public enum View: Equatable, Sendable {
            case selectOwner(UUID)
            case selectReminder(DraftReminder)
            case setDueDate(Date)
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
            case let .view(.setDueDate(date)):
                state.dueOn = InboxFormat.day.string(from: date)
                return .none
            case .binding, .view(.approveTapped), .view(.dismissTapped), .view(.closeTapped):
                return .none
            }
        }
    }
}
