import ComposableArchitecture
import Design
import EvenCore
import Foundation
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
        /// Invites addressed to the signed-in email. `GET /v1/households` answers
        /// before any membership exists — which is the only way a newcomer ever
        /// learns a seat is being held for them.
        public var invites: IdentifiedArrayOf<HouseholdInvite> = []
        public var acceptingInvite: HouseholdInvite?
        public init() {}

        public var showsBack: Bool {
            path == .create || path == .join || path == .acceptInvite
        }
    }

    public enum Path: Equatable, Sendable {
        case choice, create, inviteReveal, join, waiting, acceptInvite
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)
        case createSucceeded(Household)
        case createFailed(String)
        case joinSucceeded(Household)
        case joinFailed(String)
        case invitesLoaded([HouseholdInvite])
        case acceptSucceeded(Household)
        case acceptFailed(String)
        case declineSucceeded(inviteID: UUID)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case createTapped
            case joinTapped
            case backTapped
            case submitCreate
            case submitJoin
            case continueAfterInvite
            case acceptInviteTapped(UUID)
            case submitAcceptInvite
            case declineInviteTapped(UUID)
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
            case .view(.appear):
                // Quiet on failure: a newcomer with no invites sees exactly the
                // screen they saw before.
                return .run { [householdClient] send in
                    guard let response = try? await householdClient.list() else { return }
                    await send(.invitesLoaded(response.invites.filter { $0.status == .pending }))
                }
            case let .invitesLoaded(invites):
                state.invites = IdentifiedArray(uniqueElements: invites)
                return .none
            case let .view(.acceptInviteTapped(id)):
                guard let invite = state.invites[id: id] else { return .none }
                state.acceptingInvite = invite
                state.error = nil
                state.path = .acceptInvite
                return .none
            case .view(.submitAcceptInvite):
                guard let invite = state.acceptingInvite else { return .none }
                state.working = true
                let display = state.displayName.isEmpty ? "Me" : state.displayName
                return .run { [householdClient] send in
                    do {
                        try await send(.acceptSucceeded(await householdClient.acceptInvite(invite.id, display)))
                    } catch {
                        await send(.acceptFailed(Self.acceptCopy(for: error)))
                    }
                }
            case .acceptSucceeded:
                state.working = false
                state.path = .waiting
                return .send(.delegate(.finished))
            case let .acceptFailed(message):
                state.working = false
                state.path = .choice
                state.acceptingInvite = nil
                state.error = message
                return .none
            case let .view(.declineInviteTapped(id)):
                state.invites.remove(id: id)
                return .run { [householdClient] send in
                    try? await householdClient.declineInvite(id)
                    await send(.declineSucceeded(inviteID: id))
                }
            case .declineSucceeded:
                return .none
            case .view(.createTapped):
                state.path = .create
                state.error = nil
                return .none
            case .view(.joinTapped):
                state.path = .join
                state.error = nil
                return .none
            case .view(.backTapped):
                state.path = .choice
                state.error = nil
                state.acceptingInvite = nil
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

    static func acceptCopy(for error: Error) -> String {
        switch (error as? APIError)?.code {
        case "no_invite": return "That invite is no longer open."
        case "household_full": return "Someone took the seat first."
        case "already_in_household": return "You’re already in there."
        default: return "Couldn’t take that seat — try again."
        }
    }
}
