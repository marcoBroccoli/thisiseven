import ComposableArchitecture
import EvenCore
import Foundation
import ResetClient

/// The Sunday ritual — "the pour". Five beats that walk the household through
/// the week it just lived, then tip the beam back to level.
@Reducer
public struct ResetReducer {
    /// The beats, in order. A solo household never sees `.kind` — there is
    /// nobody on the other side of the exchange.
    public enum Beat: Int, CaseIterable, Equatable, Sendable {
        case cover
        case split
        case carry
        case kind
        case pour
    }

    /// How far the pour has got. The hold lives in the view; the reducer only
    /// learns that it finished.
    public enum PourPhase: Equatable, Sendable {
        /// Waiting for the hold.
        case waiting
        /// Pebbles are leaving the pans and the beam is levelling.
        case pouring
        /// Week closed; the new one is open and level.
        case poured
        /// The close failed — the beam stays as it was, the hold can be retried.
        case failed(String)
    }

    @ObservableState
    public struct State: Equatable {
        /// The week summary behind the cover beam. Passed in by the shell so the
        /// ritual opens on the same beam the household was just looking at.
        public var summary: Summary?
        public var me: Member?
        public var partner: Member?

        public var reset: ResetSummary?
        public var isLoading = true
        public var loadError: String?

        public var beat: Beat = .cover
        public var pour: PourPhase = .waiting

        /// What I am writing in the kind-thing beat.
        public var appreciationDraft: String = ""
        /// Did I already hand mine over? Gates the reveal of my partner's.
        public var appreciationSaved = false
        public var isSavingAppreciation = false
        /// Trades I have accepted in this sitting (id → accepted).
        public var acceptedTrades: Set<UUID> = []
        public var busyTrade: UUID?

        public init(
            summary: Summary? = nil,
            me: Member? = nil,
            partner: Member? = nil
        ) {
            self.summary = summary
            self.me = me
            self.partner = partner
        }

        public var hasPartner: Bool { partner != nil }

        /// Beats this household actually walks through.
        public var beats: [Beat] {
            hasPartner ? Beat.allCases : Beat.allCases.filter { $0 != .kind }
        }

        public var beatIndex: Int {
            beats.firstIndex(of: beat) ?? 0
        }

        public var isLastBeat: Bool {
            beat == .pour
        }

        public var weekIndex: Int {
            reset?.week.index ?? summary?.week.index ?? 1
        }

        /// My appreciation for this week, if the server already holds one.
        public var myAppreciation: Appreciation? {
            guard let me else { return nil }
            return reset?.appreciations.first { $0.fromMemberId == me.id }
        }

        public var partnerAppreciation: Appreciation? {
            guard let partner else { return nil }
            return reset?.appreciations.first { $0.fromMemberId == partner.id }
        }

        /// The partner's kind thing stays veiled until I have written mine —
        /// otherwise the first reader just answers the other one.
        public var partnerAppreciationRevealed: Bool {
            appreciationSaved || myAppreciation?.body?.isEmpty == false
        }

        public var canSaveAppreciation: Bool {
            !appreciationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !isSavingAppreciation
        }

        /// Trades this sitting can act on.
        public var myPendingTrades: [Trade] { pendingTrades(for: me) }

        /// Trades still waiting on *me* — I cannot accept one I proposed, and the
        /// API only exposes the pair, so the receiving side is the one to ask.
        public func pendingTrades(for member: Member?) -> [Trade] {
            guard let member else { return [] }
            return (reset?.trades ?? []).filter {
                !$0.accepted && !acceptedTrades.contains($0.id) && $0.toMemberId == member.id
            }
        }

        /// Beam configuration values for the pour: everything empties, the beam
        /// sits level, and the week number rolls forward.
        public var pouredOut: Bool {
            pour == .pouring || pour == .poured
        }
    }

    public enum Action: ViewAction, BindableAction {
        case view(View)
        case binding(BindingAction<State>)
        case resetLoaded(ResetSummary)
        case loadFailed(String)
        case appreciationSaved(Appreciation)
        case appreciationFailed(String)
        case tradeAccepted(Trade)
        case tradeFailed(UUID, String)
        /// `nil` week = the server said it was already poured out (409).
        case weekClosed(Week?)
        case closeFailed(String)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case advance
            case back
            case saveAppreciationTapped
            case acceptTrade(UUID)
            /// The hold reached the end — pour the week out.
            case holdCompleted
            /// "Later today" — close the sheet without closing the week.
            case dismissTapped
            /// The pour animation has played out; leave the ritual.
            case finishTapped
        }

        @CasePathable
        public enum Delegate: Equatable {
            /// Quiet exit — the week is still open.
            case dismissed
            /// The week was poured; the shell should refresh Today. `newWeek` is
            /// nil when the server had already closed it (409) — the outcome is
            /// the same, we just don't know the new week's shape yet.
            case poured(closedWeekID: UUID, newWeek: Week?)
        }
    }

    @Dependency(\.resetClient) var resetClient

    public init() {}

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .view(.appear):
                guard state.reset == nil else { return .none }
                state.isLoading = true
                state.loadError = nil
                return .run { [resetClient] send in
                    do {
                        await send(.resetLoaded(try await resetClient.fetch()))
                    } catch {
                        await send(.loadFailed(error.evenMessage))
                    }
                }

            case let .resetLoaded(reset):
                state.isLoading = false
                state.reset = reset
                // A kind thing already written this week means the exchange is
                // open — don't ask for it twice, and don't re-veil the partner's.
                if let mine = state.myAppreciation {
                    state.appreciationDraft = mine.body ?? ""
                    state.appreciationSaved = !(mine.body ?? "").isEmpty
                }
                return .none

            case let .loadFailed(message):
                state.isLoading = false
                state.loadError = message
                return .none

            case .view(.advance):
                let beats = state.beats
                guard let index = beats.firstIndex(of: state.beat),
                      index + 1 < beats.count
                else { return .none }
                state.beat = beats[index + 1]
                return .none

            case .view(.back):
                let beats = state.beats
                guard let index = beats.firstIndex(of: state.beat), index > 0 else { return .none }
                state.beat = beats[index - 1]
                return .none

            case .view(.saveAppreciationTapped):
                guard state.canSaveAppreciation, state.hasPartner else { return .none }
                state.isSavingAppreciation = true
                let body = state.appreciationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                return .run { [resetClient] send in
                    do {
                        let saved = try await resetClient.setMyAppreciation(body, false)
                        await send(.appreciationSaved(saved))
                    } catch {
                        await send(.appreciationFailed(error.evenMessage))
                    }
                }

            case let .appreciationSaved(appreciation):
                state.isSavingAppreciation = false
                state.appreciationSaved = true
                // Fold the saved row in so a reload isn't needed to see it.
                if var reset = state.reset {
                    reset.appreciations.removeAll { $0.fromMemberId == appreciation.fromMemberId }
                    reset.appreciations.append(appreciation)
                    state.reset = reset
                }
                return .none

            case let .appreciationFailed(message):
                state.isSavingAppreciation = false
                state.loadError = message
                return .none

            case let .view(.acceptTrade(id)):
                guard state.busyTrade == nil else { return .none }
                state.busyTrade = id
                return .run { [resetClient] send in
                    do {
                        await send(.tradeAccepted(try await resetClient.acceptTrade(id, true)))
                    } catch {
                        await send(.tradeFailed(id, error.evenMessage))
                    }
                }

            case let .tradeAccepted(trade):
                state.busyTrade = nil
                state.acceptedTrades.insert(trade.id)
                return .none

            case let .tradeFailed(_, message):
                state.busyTrade = nil
                state.loadError = message
                return .none

            case .view(.holdCompleted):
                guard state.pour == .waiting || state.pour.isFailed else { return .none }
                state.pour = .pouring
                let weekId = state.reset?.week.id ?? state.summary?.week.id
                return .run { [resetClient] send in
                    do {
                        let response = try await resetClient.closeWeek(weekId)
                        await send(.weekClosed(response.newWeek))
                    } catch {
                        // Someone (or an earlier tap) already poured it out. The
                        // week *is* closed — that is the outcome we wanted.
                        if (error as? APIError)?.code == "week_already_closed" {
                            await send(.weekClosed(nil))
                        } else {
                            await send(.closeFailed(error.evenMessage))
                        }
                    }
                }

            case let .weekClosed(newWeek):
                state.pour = .poured
                let closedID = state.reset?.week.id ?? state.summary?.week.id ?? UUID()
                return .send(.delegate(.poured(closedWeekID: closedID, newWeek: newWeek)))

            case let .closeFailed(message):
                state.pour = .failed(message)
                return .none

            case .view(.dismissTapped):
                return .send(.delegate(.dismissed))

            case .view(.finishTapped):
                return .send(.delegate(.dismissed))

            case .binding, .delegate:
                return .none
            }
        }
    }
}

public extension ResetReducer.PourPhase {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var message: String? {
        if case let .failed(message) = self { return message }
        return nil
    }
}

extension Error {
    /// Human sentence for the ritual's quiet error line.
    var evenMessage: String {
        (self as? LocalizedError)?.errorDescription ?? "Something got in the way."
    }
}
