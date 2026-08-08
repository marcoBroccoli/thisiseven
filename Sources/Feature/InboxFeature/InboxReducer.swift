import AuthClient
import CalendarClient
import ComposableArchitecture
import Design
import DraftsClient
import EvenCore
import Foundation
import GoogleClient
import ToastClient
import ToastUI

@Reducer
public struct InboxReducer {
    @ObservableState
    public struct State: Equatable {
        public var drafts: IdentifiedArrayOf<Draft> = []
        /// Starts true so the first frame paints a loading skeleton, not empty.
        public var isLoading = true
        /// True after the first successful drafts fetch — tab badge prefers this
        /// list over Summary’s `pendingDraftCount` once live.
        public var hasLoadedDrafts = false
        public var isCalendarLoading = false
        public var surface: Surface = .inbox
        public var calendarItems: [CalendarItem] = []
        public var calendarMonthTitle = ""
        /// First day of the loaded window (`YYYY-MM-DD`) — the month grid's anchor.
        public var calendarFrom = ""
        /// Months away from the current one; the window is derived, never stored as a `Date`.
        public var calendarMonthOffset = 0
        public var calendarLayout: CalendarLayout = .month
        /// Day filter under the month grid (`YYYY-MM-DD`); nil shows the whole month.
        public var selectedCalendarDay: String?
        public var me: Member?
        public var partner: Member?
        /// Whether *this* member has their own Gmail connected. `nil` until the
        /// first status read lands, so the inbox never flashes "connect Google"
        /// at someone who is connected.
        public var googleConnected: Bool?
        /// A fetch is in flight — the control says so and drafts reload between
        /// polls, so mail arrives batch by batch instead of in one jump.
        public var isSyncing = false
        /// Messages the running scan has taken this pass (status `scanned`).
        public var syncScanned = 0
        @Presents public var review: ReviewReducer.State?
        public init() {}

        /// Without a mailbox there is nothing to approve: the drafts surface
        /// gives way to the connect invitation entirely.
        public var showsConnectGoogle: Bool {
            googleConnected == false
        }

        /// Unattended inbox items for the main-tab badge. A tab showing the
        /// connect invitation has nothing to attend to — never badge it.
        public var pendingBadgeCount: Int {
            showsConnectGoogle ? 0 : drafts.count
        }

        public enum Surface: Equatable, Sendable {
            case inbox, calendar
        }

        /// Month grid vs. the flat day-grouped agenda — same data, two readings.
        public enum CalendarLayout: String, Equatable, Sendable, CaseIterable {
            case month, agenda

            public var label: String {
                switch self {
                case .month: "Month"
                case .agenda: "List"
                }
            }
        }
    }

    public enum Action: ViewAction {
        case view(View)
        case membersLoaded(Member?, Member?)
        case draftsLoaded([Draft])
        case review(PresentationAction<ReviewReducer.Action>)
        case dismiss(UUID)
        case approved(UUID)
        case dismissed(UUID)
        case calendarLoaded(CalendarResponse)
        /// The caller's own Google standing, plus whether a scan is already
        /// running (the background poller may have started one).
        case googleStatusLoaded(connected: Bool, syncing: Bool)
        /// Quiet on purpose — an unreadable status keeps the last known one.
        case googleStatusFailed
        case syncProgressed(scanned: Int)
        case syncFinished(created: Int)
        /// Connected / disconnected elsewhere (Profile → Connections). A
        /// disconnect flushes the mailbox server-side, so the list empties too.
        case googleConnectionChanged(Bool)
        /// Toast — `ToastClient` → feature `.evenToastHost()`.
        case presentToast(Toast)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case refresh
            case selectDraft(UUID)
            case selectSurface(State.Surface)
            /// Swipe-approve: take the draft exactly as Gmail suggested it.
            case approveDraft(UUID)
            /// Swipe-dismiss: same call the review sheet's "Dismiss draft" makes.
            case dismissDraft(UUID)
            case selectCalendarLayout(State.CalendarLayout)
            case stepCalendarMonth(Int)
            case selectCalendarDay(String?)
            /// Manual "check Gmail now" — starts a scan and follows it.
            case fetchTapped
            /// No mailbox yet: hand the ask to the one Connections flow.
            case connectGoogleTapped
        }

        @CasePathable
        public enum Delegate: Equatable {
            /// The app owns the OAuth flow (Profile → Connections); the inbox
            /// only asks for it. Nothing about Google is re-implemented here.
            case connectGoogleRequested
        }
    }

    @Dependency(\.draftsClient) var draftsClient
    @Dependency(\.calendarClient) var calendarClient
    @Dependency(\.authClient) var authClient
    @Dependency(\.googleClient) var googleClient
    @Dependency(\.toastClient) var toastClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.context) var context

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appear):
                // Don't flash skeleton when drafts are already on screen (tab revisit).
                if state.drafts.isEmpty {
                    state.isLoading = true
                }
                return .merge(
                    loadDrafts(),
                    loadGoogleStatus(),
                    .run { [authClient] send in
                        let members = await authClient.householdMembers()
                        await send(.membersLoaded(members.me, members.partner))
                    }
                )

            case let .membersLoaded(me, partner):
                state.me = me
                state.partner = partner
                return .none

            case let .draftsLoaded(drafts):
                state.isLoading = false
                state.hasLoadedDrafts = true
                state.drafts = IdentifiedArray(uniqueElements: drafts)
                return .none

            case let .view(.selectDraft(id)):
                guard let draft = state.drafts[id: id] else { return .none }
                state.review = ReviewReducer.State(draft: draft, me: state.me, partner: state.partner)
                return .none

            case .review(.presented(.view(.closeTapped))):
                state.review = nil
                return .none

            case .review(.presented(.view(.approveTapped))):
                guard let review = state.review else { return .none }
                let id = review.draft.id
                let body = EvenAPIClient.DraftPatchBody(
                    title: review.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    ownerMemberId: review.ownerMemberId,
                    dueOn: review.dueOn,
                    reminder: review.reminder
                )
                state.review = nil
                return approve(id, body)

            case let .view(.approveDraft(id)):
                // "As-is" still patches — the sheet and the swipe must be one
                // path, so the draft's own values go over the same two calls.
                guard let draft = state.drafts[id: id] else { return .none }
                return approve(
                    id,
                    EvenAPIClient.DraftPatchBody(
                        title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        ownerMemberId: draft.ownerMemberId,
                        dueOn: draft.dueOn,
                        reminder: draft.reminder
                    )
                )

            case let .view(.dismissDraft(id)):
                guard state.drafts[id: id] != nil else { return .none }
                return .send(.dismiss(id))

            case .review(.presented(.view(.dismissTapped))):
                guard let review = state.review else { return .none }
                let id = review.draft.id
                state.review = nil
                return .send(.dismiss(id))

            case .review:
                return .none

            case let .dismiss(id):
                return .run { [draftsClient] send in
                    do {
                        _ = try await draftsClient.dismiss(id)
                        await send(.dismissed(id))
                    } catch {
                        await send(.presentToast(.inboxFailure(error, .dismiss)))
                    }
                }

            case let .approved(id):
                state.drafts.remove(id: id)
                return toastEffect(
                    Toast(message: "Approved → task + calendar event", tone: .success)
                )

            case let .dismissed(id):
                state.drafts.remove(id: id)
                return .none

            case .view(.refresh):
                switch state.surface {
                case .inbox:
                    // Empty inbox: show skeleton (same as appear). With content,
                    // keep the list and let `.refreshable` own the spinner.
                    let empty = state.drafts.isEmpty
                    if empty { state.isLoading = true }
                    return .merge(
                        loadDrafts(surviveStoreTaskCancellation: empty),
                        loadGoogleStatus()
                    )
                case .calendar:
                    let empty = state.calendarItems.isEmpty
                    if empty { state.isCalendarLoading = true }
                    return loadCalendar(
                        monthOffset: state.calendarMonthOffset,
                        surviveStoreTaskCancellation: empty
                    )
                }

            case let .view(.selectSurface(surface)):
                state.surface = surface
                guard surface == .calendar else { return .none }
                if state.calendarItems.isEmpty {
                    state.isCalendarLoading = true
                }
                return loadCalendar(monthOffset: state.calendarMonthOffset)

            case let .view(.selectCalendarLayout(layout)):
                state.calendarLayout = layout
                return .none

            case let .view(.stepCalendarMonth(step)):
                state.calendarMonthOffset += step
                state.selectedCalendarDay = nil
                state.calendarItems = []
                state.isCalendarLoading = true
                return loadCalendar(monthOffset: state.calendarMonthOffset)

            case let .view(.selectCalendarDay(day)):
                // Same day twice clears the filter — the grid is a filter, not a mode.
                state.selectedCalendarDay = state.selectedCalendarDay == day ? nil : day
                return .none

            case let .calendarLoaded(response):
                state.isCalendarLoading = false
                state.calendarItems = response.items
                state.calendarFrom = response.from
                state.calendarMonthTitle = monthTitle(from: response.from)
                return .none

            case let .googleStatusLoaded(connected, syncing):
                state.googleConnected = connected
                guard connected else {
                    // Server truth: a disconnected mailbox has no drafts left.
                    // Never keep a cached copy on screen behind the invitation.
                    return flushLocalInbox(&state)
                }
                // The background poller may already be scanning — adopt that
                // job rather than showing an idle control over a live sync.
                guard syncing, !state.isSyncing else { return .none }
                state.isSyncing = true
                state.syncScanned = 0
                return followSync()

            case .googleStatusFailed:
                return .none

            case let .googleConnectionChanged(connected):
                state.googleConnected = connected
                state.isSyncing = false
                guard connected else { return flushLocalInbox(&state) }
                state.isLoading = state.drafts.isEmpty
                return loadDrafts()

            case .view(.fetchTapped):
                guard state.googleConnected == true, !state.isSyncing else { return .none }
                state.isSyncing = true
                state.syncScanned = 0
                return startSync()

            case .view(.connectGoogleTapped):
                return .send(.delegate(.connectGoogleRequested))

            case let .syncProgressed(scanned):
                state.syncScanned = scanned
                // Drafts land in the database batch by batch — read them as
                // they appear rather than waiting for the whole scan.
                return loadDrafts()

            case let .syncFinished(created):
                state.isSyncing = false
                return .merge(
                    loadDrafts(),
                    toastEffect(Toast(message: InboxSyncCopy.finished(created)))
                )

            case .delegate:
                return .none

            case let .presentToast(toast):
                if toast.tone == .error {
                    state.isLoading = false
                    state.isCalendarLoading = false
                    state.isSyncing = false
                }
                return toastEffect(toast)
            }
        }
        .ifLet(\.$review, action: \.review) {
            ReviewReducer()
        }
    }

    private enum CancelID { case drafts, calendar, googleStatus, sync }

    /// How a running scan is followed: a poll every couple of seconds, capped
    /// well inside the server's own four-minute job timeout.
    private enum SyncPoll {
        static let interval: Duration = .seconds(2)
        static let maxPolls = 90
    }

    /// The caller's Google standing is one bit the inbox needs — fetch or
    /// invite. It reads it itself on appear / refresh rather than borrowing
    /// Profile's Connections state: no shared singleton, no cross-tab coupling.
    private func loadGoogleStatus() -> Effect<Action> {
        .run { [googleClient] send in
            do {
                let status = try await googleClient.status()
                await send(
                    .googleStatusLoaded(connected: status.connected, syncing: status.isSyncing),
                    animation: EvenMotion.reveal
                )
            } catch {
                // Quiet: a status we could not read must not toast over the
                // list, and the inbox keeps whatever it last knew.
                await send(.googleStatusFailed)
            }
        }
        .cancellable(id: CancelID.googleStatus, cancelInFlight: true)
    }

    /// Empties the on-device list to match a mailbox that is gone. The server
    /// deleted those drafts on disconnect; showing them would be a lie.
    private func flushLocalInbox(_ state: inout State) -> Effect<Action> {
        state.drafts = []
        state.isSyncing = false
        state.isLoading = false
        state.syncScanned = 0
        return .merge(.cancel(id: CancelID.sync), .cancel(id: CancelID.drafts))
    }

    private func startSync() -> Effect<Action> {
        .run { [googleClient, clock] send in
            _ = try await googleClient.startSync()
            try await Self.follow(googleClient: googleClient, clock: clock, send: send)
        } catch: { error, send in
            guard !(error is CancellationError) else { return }
            await send(.presentToast(.inboxFailure(error, .fetch)))
        }
        .cancellable(id: CancelID.sync, cancelInFlight: true)
    }

    /// Joins a scan that is already running (started by the poller, or by this
    /// member on another device) without starting a second one.
    private func followSync() -> Effect<Action> {
        .run { [googleClient, clock] send in
            try await Self.follow(googleClient: googleClient, clock: clock, send: send)
        } catch: { error, send in
            guard !(error is CancellationError) else { return }
            await send(.presentToast(.inboxFailure(error, .fetch)))
        }
        .cancellable(id: CancelID.sync, cancelInFlight: true)
    }

    /// Polls the scan job, telling the inbox what has been taken so far. Each
    /// report reloads the drafts list, so the mail pours in rather than
    /// arriving all at once when the job ends.
    private static func follow(
        googleClient: GoogleClient,
        clock: any Clock<Duration>,
        send: Send<Action>
    ) async throws {
        var created = 0
        for _ in 0 ..< SyncPoll.maxPolls {
            try await clock.sleep(for: SyncPoll.interval)
            let status = try await googleClient.status()
            created = status.created ?? created
            await send(.syncProgressed(scanned: status.scanned ?? 0), animation: EvenMotion.reveal)
            if !status.isSyncing { break }
        }
        await send(.syncFinished(created: created), animation: EvenMotion.reveal)
    }

    /// - Parameter surviveStoreTaskCancellation: Empty pull-to-refresh swaps in a
    ///   skeleton; SwiftUI then cancels the refreshable task. That cancels the
    ///   `StoreTask` from `await send(.refresh).finish()`, and TCA `Send` drops
    ///   actions while cancelled — loading would stick. In live/preview we hop
    ///   the fetch off that task. Tests keep a structured await for TestStore.
    private func loadDrafts(surviveStoreTaskCancellation: Bool = false) -> Effect<Action> {
        .run { [draftsClient, context, surviveStoreTaskCancellation] send in
            await Self.runFetch(
                surviveStoreTaskCancellation: surviveStoreTaskCancellation,
                context: context,
                send: send,
                fetch: { try await draftsClient.pending() },
                success: { .draftsLoaded($0) },
                failure: { .presentToast(.inboxFailure($0, .load)) }
            )
        }
        .cancellable(id: CancelID.drafts, cancelInFlight: true)
    }

    /// One approve = patch then approve. The review sheet and the swipe both
    /// land here so "as-is" can never drift from "reviewed".
    private func approve(_ id: UUID, _ body: EvenAPIClient.DraftPatchBody) -> Effect<Action> {
        .run { [draftsClient] send in
            do {
                _ = try await draftsClient.update(id, body)
                _ = try await draftsClient.approve(id)
                await send(.approved(id))
            } catch {
                await send(.presentToast(.inboxFailure(error, .approve)))
            }
        }
    }

    private func loadCalendar(
        monthOffset: Int = 0,
        surviveStoreTaskCancellation: Bool = false
    ) -> Effect<Action> {
        .run { [calendarClient, context, surviveStoreTaskCancellation, monthOffset] send in
            await Self.runFetch(
                surviveStoreTaskCancellation: surviveStoreTaskCancellation,
                context: context,
                send: send,
                fetch: {
                    let cal = Calendar.current
                    let now = Date()
                    let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
                    let start = cal.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
                    let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
                    // Civil days, local calendar. `ISO8601DateFormatter` is UTC
                    // by default, which shifted the window (and the month title)
                    // a day back for every timezone east of GMT.
                    return try await calendarClient.window(
                        InboxFormat.day.string(from: start),
                        InboxFormat.day.string(from: end)
                    )
                },
                success: { .calendarLoaded($0) },
                failure: { .presentToast(.inboxFailure($0, .calendar)) }
            )
        }
        .cancellable(id: CancelID.calendar, cancelInFlight: true)
    }

    private static func runFetch<Value: Sendable>(
        surviveStoreTaskCancellation: Bool,
        context: DependencyContext,
        send: Send<Action>,
        fetch: @escaping @Sendable () async throws -> Value,
        success: @escaping @Sendable (Value) -> Action,
        failure: @escaping @Sendable (Error) -> Action
    ) async {
        let fulfill: @MainActor @Sendable (Result<Value, Error>) -> Void = { result in
            switch result {
            case let .success(value):
                send(success(value))
            case let .failure(error) where error is CancellationError:
                break
            case let .failure(error):
                send(failure(error))
            }
        }

        if surviveStoreTaskCancellation, context != .test {
            Task { @MainActor in
                fulfill(await Result { try await fetch() })
            }
        } else {
            await fulfill(await Result { try await fetch() })
        }
    }

    private func toastEffect(_ toast: Toast) -> Effect<Action> {
        .run { [toastClient] _ in
            await toastClient.show(toast)
        }
    }

    private func monthTitle(from iso: String) -> String {
        guard let date = InboxFormat.day.date(from: iso) else { return iso }
        return InboxFormat.monthYear.string(from: date)
    }
}

/// What a finished fetch says. Calm, countable, never triumphant.
public enum InboxSyncCopy {
    public static func finished(_ created: Int) -> String {
        switch created {
        case ...0: "Gmail checked — nothing new."
        case 1: "1 new draft from Gmail."
        default: "\(created) new drafts from Gmail."
        }
    }
}

extension Toast {
    enum InboxFailure {
        case load, approve, dismiss, calendar, fetch

        var fallback: String {
            switch self {
            case .load: "Couldn’t load inbox"
            case .approve: "Couldn’t approve draft"
            case .dismiss: "Couldn’t dismiss draft"
            case .calendar: "Couldn’t load calendar"
            case .fetch: "Couldn’t check Gmail"
            }
        }
    }

    static func inboxFailure(_ error: Error, _ kind: InboxFailure) -> Toast {
        .failure(from: error, offline: "Couldn’t reach Even", fallback: kind.fallback)
    }
}
