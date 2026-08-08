import ComposableArchitecture
import EvenCore
import Foundation
import HouseholdClient
import ToastClient
import ToastUI

/// Your places. A household holds exactly two people; a person may hold several
/// households (`docs/product/API.md` → Active household on `/v1/*`).
///
/// Nothing crosses between them — tasks, drafts, money and the realtime channel
/// are all scoped to whichever one is active here.
@Reducer
public struct HouseholdsReducer {
    @ObservableState
    public struct State: Equatable {
        public var path: Path = .list
        public var households: IdentifiedArrayOf<HouseholdRow> = []
        /// Invites addressed to the signed-in email, minus places you're in.
        public var invites: IdentifiedArrayOf<HouseholdInvite> = []
        public var isLoading = true
        /// The name this person already answers to — the default when they take
        /// a seat somewhere new.
        public var myDisplayName = ""
        /// The one household showing its invite code / seat controls.
        public var expandedHouseholdID: UUID?
        public var inviteEmail = ""
        /// A row waiting on the server (invite, revoke, switch).
        public var busyHouseholdID: UUID?
        public var busyInviteID: UUID?
        public var newHouseholdName = ""
        public var newDisplayName = ""
        /// The code somebody else read out to you. Held uppercased — the server
        /// upper-cases it too, so what you see is what it looks up.
        public var joinInviteCode = ""
        public var joinDisplayName = ""
        public var acceptingInvite: HouseholdInvite?
        public var acceptDisplayName = ""
        public var working = false
        /// The household whose "leave" confirmation is on screen.
        public var leavingHousehold: HouseholdRow?
        /// The household `/v1/me` just answered for — the server's own word on
        /// which one is open. Persistence is `ActiveHousehold` in EvenCore (the
        /// single source of truth `EvenAPIClient` and the socket both read); the
        /// clients write it, this only mirrors it.
        public var activeHouseholdID: UUID?

        public init() {}

        /// With nothing pinned yet the server answers for the most recently
        /// joined household — the last row `GET /v1/households` returns.
        public var effectiveActiveID: UUID? {
            if let activeHouseholdID,
               households.contains(where: { $0.id == activeHouseholdID })
            {
                return activeHouseholdID
            }
            return households.last?.id
        }

        public func isActive(_ row: HouseholdRow) -> Bool {
            effectiveActiveID == row.id
        }

        public var showsBack: Bool {
            path != .list
        }

        public var canSubmitCreate: Bool {
            !newHouseholdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working
        }

        public var canSubmitAccept: Bool {
            !acceptDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working
        }

        public var canSubmitJoin: Bool {
            !joinInviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working
        }

        /// A row only takes an address while a seat is free and nobody is on it.
        public func canInvite(_ row: HouseholdRow) -> Bool {
            row.hasFreeSeat && row.pendingInviteEmail == nil
        }

        /// What leaving costs, said plainly. The last line only appears when
        /// there is nobody left to keep the place open.
        public var leaveConfirmationMessage: String {
            guard let row = leavingHousehold else { return "" }
            var lines = [
                "Your open todos there are archived, and your Gmail for this household disconnects.",
            ]
            if row.memberCount > 1 {
                lines.append("The shared calendar hands over to your partner, and everything you settled together stays.")
            } else {
                lines.append("You’re the only one here, so this deletes the household.")
            }
            return lines.joined(separator: " ")
        }
    }

    public enum Path: Equatable, Sendable {
        case list, create, accept, join
    }

    /// What `/v1/me` says about the household currently open, and the name the
    /// caller goes by there.
    public struct OpenHousehold: Equatable, Sendable {
        public var householdID: UUID?
        public var displayName: String?

        public init(householdID: UUID? = nil, displayName: String? = nil) {
            self.householdID = householdID
            self.displayName = displayName
        }
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)
        case householdsLoaded(HouseholdsResponse, open: OpenHousehold)
        case loadFailed
        case inviteSucceeded(HouseholdInvite)
        case inviteFailed(String)
        case revokeSucceeded(householdID: UUID)
        case revokeFailed(String)
        case switchSucceeded(householdID: UUID)
        case switchFailed(String)
        case acceptSucceeded(Household)
        case acceptFailed(String)
        case declineSucceeded(inviteID: UUID)
        case declineFailed(String)
        case createSucceeded(Household)
        case createFailed(String)
        case joinSucceeded(Household)
        case joinFailed(String)
        case leaveSucceeded(householdID: UUID, deleted: Bool, wasOpen: Bool)
        case leaveFailed(String)
        case presentToast(Toast)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case refresh
            case backTapped
            case selectHousehold(UUID)
            case toggleExpanded(UUID)
            case submitInvite(UUID)
            case revokeInvite(UUID)
            case inviteCodeCopied
            case createTapped
            case submitCreate
            case joinTapped
            case submitJoin
            case acceptTapped(UUID)
            case submitAccept
            case declineTapped(UUID)
            case leaveTapped(UUID)
            case confirmLeave
            case cancelLeave
        }

        @CasePathable
        public enum Delegate: Equatable {
            /// The app is now looking at a different household — everything
            /// household-scoped has to be pulled again, socket included.
            case activeHouseholdChanged(UUID)
            /// The last seat is given up: there is no household to show, so the
            /// app has to go back to setting one up.
            case leftLastHousehold
        }
    }

    @Dependency(\.householdClient) var householdClient
    @Dependency(\.toastClient) var toastClient

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            // Codes are read out, not typed carefully — hold the field in the
            // shape the server looks up so a paste reads the same as typing.
            case .binding(\.joinInviteCode):
                state.joinInviteCode = state.joinInviteCode.uppercased()
                return .none

            case .binding:
                return .none

            case .view(.appear), .view(.refresh):
                if state.households.isEmpty {
                    state.isLoading = true
                }
                return load()

            case let .householdsLoaded(response, open):
                state.isLoading = false
                state.households = IdentifiedArray(uniqueElements: response.households)
                state.invites = IdentifiedArray(
                    uniqueElements: response.invites.filter { $0.status == .pending }
                )
                state.activeHouseholdID = open.householdID
                if let name = open.displayName, !name.isEmpty {
                    state.myDisplayName = name
                }
                return .none

            case .loadFailed:
                state.isLoading = false
                return toastEffect(.init(message: "couldn’t load your households", tone: .error))

            case let .view(.selectHousehold(id)):
                guard let row = state.households[id: id], !state.isActive(row) else { return .none }
                guard state.busyHouseholdID == nil else { return .none }
                state.busyHouseholdID = id
                return .run { [householdClient] send in
                    do {
                        _ = try await householdClient.setActive(id)
                        await send(.switchSucceeded(householdID: id))
                    } catch {
                        await send(.switchFailed(Self.copy(for: error, fallback: "couldn’t switch households")))
                    }
                }

            case let .switchSucceeded(householdID):
                state.busyHouseholdID = nil
                state.activeHouseholdID = householdID
                state.expandedHouseholdID = nil
                let name = state.households[id: householdID]?.name ?? "that household"
                return .merge(
                    .send(.delegate(.activeHouseholdChanged(householdID))),
                    toastEffect(.init(message: "now looking at \(name)"))
                )

            case let .switchFailed(message):
                state.busyHouseholdID = nil
                return toastEffect(.init(message: message, tone: .error))

            case let .view(.toggleExpanded(id)):
                state.expandedHouseholdID = state.expandedHouseholdID == id ? nil : id
                state.inviteEmail = ""
                return .none

            case let .view(.submitInvite(id)):
                let email = state.inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !email.isEmpty else { return .none }
                guard state.busyHouseholdID == nil else { return .none }
                state.busyHouseholdID = id
                return .run { [householdClient] send in
                    do {
                        let invite = try await householdClient.invite(id, email)
                        await send(.inviteSucceeded(invite))
                    } catch {
                        await send(.inviteFailed(Self.inviteCopy(for: error)))
                    }
                }

            case let .inviteSucceeded(invite):
                state.busyHouseholdID = nil
                state.inviteEmail = ""
                state.households[id: invite.householdId]?.pendingInviteEmail = invite.email
                return toastEffect(.init(
                    message: "invited \(invite.email) — they’ll see it when they sign in",
                    tone: .success
                ))

            case let .inviteFailed(message):
                state.busyHouseholdID = nil
                return toastEffect(.init(message: message, tone: .error))

            case let .view(.revokeInvite(id)):
                guard state.busyHouseholdID == nil else { return .none }
                state.busyHouseholdID = id
                return .run { [householdClient] send in
                    do {
                        try await householdClient.revokeInvite(id)
                        await send(.revokeSucceeded(householdID: id))
                    } catch {
                        await send(.revokeFailed(Self.copy(for: error, fallback: "couldn’t take that invite back")))
                    }
                }

            case let .revokeSucceeded(householdID):
                state.busyHouseholdID = nil
                state.households[id: householdID]?.pendingInviteEmail = nil
                return toastEffect(.init(message: "invite withdrawn — the seat is free again"))

            case let .revokeFailed(message):
                state.busyHouseholdID = nil
                return toastEffect(.init(message: message, tone: .error))

            case .view(.inviteCodeCopied):
                return toastEffect(.init(message: "invite code copied"))

            case .view(.createTapped):
                state.path = .create
                state.newHouseholdName = ""
                state.newDisplayName = state.myDisplayName
                return .none

            case .view(.submitCreate):
                guard state.canSubmitCreate else { return .none }
                state.working = true
                let name = state.newHouseholdName.trimmingCharacters(in: .whitespacesAndNewlines)
                let display = Self.displayName(state.newDisplayName, fallback: state.myDisplayName)
                return .run { [householdClient] send in
                    do {
                        let household = try await householdClient.create(name, display)
                        await send(.createSucceeded(household))
                    } catch {
                        await send(.createFailed(Self.copy(for: error, fallback: "couldn’t start that household")))
                    }
                }

            case let .createSucceeded(household):
                state.working = false
                state.path = .list
                // The client already pinned it (`ActiveHousehold`) — a place you
                // just made is the place you are looking at.
                state.activeHouseholdID = household.id
                return .merge(
                    .send(.delegate(.activeHouseholdChanged(household.id))),
                    load(),
                    toastEffect(.init(message: "\(household.name) is yours — hand over the code", tone: .success))
                )

            case let .createFailed(message):
                state.working = false
                return toastEffect(.init(message: message, tone: .error))

            case .view(.joinTapped):
                state.path = .join
                state.joinInviteCode = ""
                state.joinDisplayName = state.myDisplayName
                return .none

            case .view(.submitJoin):
                guard state.canSubmitJoin else { return .none }
                state.working = true
                let code = state.joinInviteCode
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                let display = Self.displayName(state.joinDisplayName, fallback: state.myDisplayName)
                return .run { [householdClient] send in
                    do {
                        let household = try await householdClient.join(code, display)
                        await send(.joinSucceeded(household))
                    } catch {
                        await send(.joinFailed(Self.joinCopy(for: error)))
                    }
                }

            case let .joinSucceeded(household):
                state.working = false
                state.path = .list
                state.joinInviteCode = ""
                // The client already pinned it (`ActiveHousehold`) — the place
                // you just walked into is the place you are looking at.
                state.activeHouseholdID = household.id
                return .merge(
                    .send(.delegate(.activeHouseholdChanged(household.id))),
                    load(),
                    toastEffect(.init(message: "you’re in \(household.name)", tone: .success))
                )

            case let .joinFailed(message):
                // Stay on the form: a mistyped code is one character away from
                // working, and bouncing back to the list loses the name too.
                state.working = false
                return toastEffect(.init(message: message, tone: .error))

            case let .view(.acceptTapped(id)):
                guard let invite = state.invites[id: id] else { return .none }
                state.acceptingInvite = invite
                state.acceptDisplayName = state.myDisplayName
                state.path = .accept
                return .none

            case .view(.submitAccept):
                guard state.canSubmitAccept, let invite = state.acceptingInvite else { return .none }
                state.working = true
                let display = Self.displayName(state.acceptDisplayName, fallback: state.myDisplayName)
                return .run { [householdClient] send in
                    do {
                        let household = try await householdClient.acceptInvite(invite.id, display)
                        await send(.acceptSucceeded(household))
                    } catch {
                        await send(.acceptFailed(Self.acceptCopy(for: error)))
                    }
                }

            case let .acceptSucceeded(household):
                state.working = false
                state.path = .list
                if let invite = state.acceptingInvite {
                    state.invites.remove(id: invite.id)
                }
                state.acceptingInvite = nil
                state.activeHouseholdID = household.id
                return .merge(
                    .send(.delegate(.activeHouseholdChanged(household.id))),
                    load(),
                    toastEffect(.init(message: "you’re in \(household.name)", tone: .success))
                )

            case let .acceptFailed(message):
                state.working = false
                state.path = .list
                state.acceptingInvite = nil
                return .merge(load(), toastEffect(.init(message: message, tone: .error)))

            case let .view(.declineTapped(id)):
                guard state.busyInviteID == nil else { return .none }
                state.busyInviteID = id
                return .run { [householdClient] send in
                    do {
                        try await householdClient.declineInvite(id)
                        await send(.declineSucceeded(inviteID: id))
                    } catch {
                        await send(.declineFailed(Self.acceptCopy(for: error)))
                    }
                }

            case let .declineSucceeded(inviteID):
                state.busyInviteID = nil
                state.invites.remove(id: inviteID)
                return toastEffect(.init(message: "invite declined"))

            case let .declineFailed(message):
                state.busyInviteID = nil
                return toastEffect(.init(message: message, tone: .error))

            case let .view(.leaveTapped(id)):
                state.leavingHousehold = state.households[id: id]
                return .none

            case .view(.cancelLeave):
                state.leavingHousehold = nil
                return .none

            case .view(.confirmLeave):
                guard let row = state.leavingHousehold else { return .none }
                state.leavingHousehold = nil
                state.busyHouseholdID = row.id
                // Whether this was the household on screen decides where the app
                // looks next — read it before the row is gone.
                let wasOpen = state.effectiveActiveID == row.id
                return .run { [householdClient] send in
                    do {
                        let result = try await householdClient.leave(row.id)
                        await send(.leaveSucceeded(
                            householdID: row.id,
                            deleted: result.householdDeleted,
                            wasOpen: wasOpen
                        ))
                    } catch {
                        await send(.leaveFailed(Self.leaveCopy(for: error)))
                    }
                }

            case let .leaveSucceeded(householdID, deleted, wasOpen):
                state.busyHouseholdID = nil
                let name = state.households[id: householdID]?.name ?? "that household"
                state.households.remove(id: householdID)
                state.expandedHouseholdID = nil
                if state.activeHouseholdID == householdID {
                    state.activeHouseholdID = nil
                }
                let farewell = Toast(
                    message: deleted ? "\(name) is closed" : "you’ve left \(name)"
                )

                guard wasOpen else {
                    return toastEffect(farewell)
                }
                // The app was showing the household just left. Fall to another
                // one — or, with nowhere left to stand, back to setup.
                guard let next = state.households.last else {
                    return .merge(
                        .send(.delegate(.leftLastHousehold)),
                        toastEffect(farewell)
                    )
                }
                state.busyHouseholdID = next.id
                return .merge(
                    .run { [householdClient] send in
                        do {
                            _ = try await householdClient.setActive(next.id)
                            await send(.switchSucceeded(householdID: next.id))
                        } catch {
                            await send(.switchFailed(Self.copy(
                                for: error, fallback: "couldn’t open your other household"
                            )))
                        }
                    },
                    toastEffect(farewell)
                )

            case let .leaveFailed(message):
                state.busyHouseholdID = nil
                return .merge(load(), toastEffect(.init(message: message, tone: .error)))

            case .view(.backTapped):
                state.path = .list
                state.acceptingInvite = nil
                state.working = false
                return .none

            case let .presentToast(toast):
                return .run { [toastClient] _ in await toastClient.show(toast) }

            case .delegate:
                return .none
            }
        }
    }

    /// `/v1/me` is the honest answer to "which household is open?" — it is
    /// resolved with the very header every other request carries.
    private func load() -> Effect<Action> {
        .run { [householdClient] send in
            do {
                let response = try await householdClient.list()
                let me = try? await householdClient.loadProfile()
                await send(.householdsLoaded(response, open: .init(
                    householdID: me?.household?.id,
                    displayName: me?.member?.displayName ?? me?.household?.me?.displayName
                )))
            } catch {
                await send(.loadFailed)
            }
        }
    }

    private func toastEffect(_ toast: Toast) -> Effect<Action> {
        .run { [toastClient] _ in await toastClient.show(toast) }
    }

    private static func displayName(_ draft: String, fallback: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let backup = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return backup.isEmpty ? "Me" : backup
    }

    // MARK: Error copy

    static func inviteCopy(for error: Error) -> String {
        switch (error as? APIError)?.code {
        case "invalid_email": return "that doesn’t look like an email address"
        case "invite_pending": return "there’s already an invite out — withdraw it first"
        case "household_full": return "both seats are taken here"
        case "self_invite": return "that’s your own address"
        case "not_in_household": return "you’re not in that household"
        default: return copy(for: error, fallback: "couldn’t send that invite")
        }
    }

    static func acceptCopy(for error: Error) -> String {
        switch (error as? APIError)?.code {
        case "no_invite": return "that invite is no longer open"
        case "household_full": return "someone took the seat first"
        case "already_in_household": return "you’re already in there"
        default: return copy(for: error, fallback: "couldn’t answer that invite")
        }
    }

    /// A code is somebody reading six characters aloud — say what went wrong in
    /// the same voice, and never blame the person holding the phone.
    static func joinCopy(for error: Error) -> String {
        switch (error as? APIError)?.code {
        case "bad_code": return "that code doesn’t open anything — check it with your partner"
        case "household_full": return "both seats are taken here"
        case "already_in_household": return "you’re already in that household"
        case "missing_fields": return "a code and a name, please"
        default: return copy(for: error, fallback: "couldn’t join that household")
        }
    }

    static func leaveCopy(for error: Error) -> String {
        switch (error as? APIError)?.code {
        case "not_in_household": return "you’ve already left that household"
        default: return copy(for: error, fallback: "couldn’t leave that household")
        }
    }

    static func copy(for error: Error, fallback: String) -> String {
        if let apiError = error as? APIError, case .transport = apiError {
            return "can’t reach the house server"
        }
        return fallback
    }
}
