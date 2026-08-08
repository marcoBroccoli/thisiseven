import ComposableArchitecture
import EvenCore
import Foundation
import HouseholdRealtimeClient
import InboxFeature
import ProfileFeature
import ResetFeature
import TodayFeature

@Reducer
public struct MainTabReducer {
    @ObservableState
    public struct State: Equatable {
        public var inbox = InboxReducer.State()
        public var today = TodayReducer.State()
        public var profile = ProfileReducer.State()
        public var tab: Tab = .today
        /// The Sunday ritual, over the tabs.
        @Presents public var reset: ResetReducer.State?
        /// The week we last poured out — survives launches so a closed week
        /// never asks to be closed again.
        @Shared(.appStorage("evenResetLastPouredWeekID")) public var lastPouredWeekID = ""
        /// "Later today" only holds until the next appear — by design.
        public var resetDismissed = false

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
        case reset(PresentationAction<ResetReducer.Action>)
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
    @Dependency(\.date.now) var now
    @Dependency(\.calendar) var calendar

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.inbox, action: \.inbox) { InboxReducer() }
        Scope(state: \.today, action: \.today) { TodayReducer() }
        Scope(state: \.profile, action: \.profile) { ProfileReducer() }
        Reduce { state, action in
            switch action {
            case .view(.appear):
                // A quiet dismissal lasts one appearance, not the day — the
                // ritual is the whole point of Sunday.
                state.resetDismissed = false
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

            case let .today(.summaryLoaded(summary)):
                presentResetIfDue(&state, summary: summary)
                return .none

            case .today(.membersLoaded):
                // Members can land after the summary — keep the sheet's copy honest.
                let me = state.today.me
                let partner = state.today.partner
                state.reset?.me = me
                state.reset?.partner = partner
                return .none

            case let .reset(.presented(.delegate(.poured(closedWeekID, _)))):
                state.$lastPouredWeekID.withLock { $0 = closedWeekID.uuidString }
                // Today still shows the week that just ended; pull the new one.
                return .send(.today(.view(.refresh)))

            case .reset(.presented(.delegate(.dismissed))):
                state.resetDismissed = true
                state.reset = nil
                return .none

            case .inbox(.delegate(.connectGoogleRequested)):
                // One Connections flow, and it lives on Profile. The inbox asks;
                // Profile's card owns the OAuth and the connected state after it.
                state.tab = .profile
                return .send(.profile(.view(.connectGoogleTapped)))

            case .profile(.connections(.connectSucceeded)):
                return .send(.inbox(.googleConnectionChanged(true)))

            case .profile(.connections(.disconnectSucceeded)):
                // The server flushed that mailbox's drafts — the inbox must not
                // keep showing a cached copy of mail it can no longer refresh.
                return .send(.inbox(.googleConnectionChanged(false)))

            case .profile(.delegate(.signedOut)):
                return .send(.delegate(.signedOut))

            case .delegate, .reset:
                return .none

            case .inbox, .today, .profile:
                return .none
            }
        }
        .ifLet(\.$reset, action: \.reset) { ResetReducer() }
    }

    /// Sunday, or a week that has outstayed its seven days. Never for a week we
    /// already poured, never over a dismissal, never twice.
    private func presentResetIfDue(_ state: inout State, summary: Summary) {
        guard state.reset == nil, !state.resetDismissed else { return }
        guard state.lastPouredWeekID != summary.week.id.uuidString else { return }
        guard Self.isResetDue(
            weekStartedOn: summary.week.startedOn, now: now, calendar: calendar
        ) else { return }

        state.reset = ResetReducer.State(
            summary: summary,
            me: state.today.me,
            partner: state.today.partner
        )
    }

    /// Due on Sunday, or as soon as the open week is seven days old — weeks that
    /// never closed must ask on the next launch, not wait for the weekend.
    public static func isResetDue(
        weekStartedOn: String,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        if calendar.component(.weekday, from: now) == 1 { return true }
        guard let started = weekStartDateFormatter.date(from: weekStartedOn) else { return false }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: started), to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days >= 7
    }

    private static let weekStartDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
