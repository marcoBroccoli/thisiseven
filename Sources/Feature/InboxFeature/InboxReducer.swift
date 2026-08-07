import AuthClient
import CalendarClient
import ComposableArchitecture
import DraftsClient
import EvenCore
import Foundation
import ToastClient
import ToastUI

@Reducer
public struct InboxReducer {
    @ObservableState
    public struct State: Equatable {
        public var drafts: IdentifiedArrayOf<Draft> = []
        /// Starts true so the first frame paints a loading skeleton, not empty.
        public var isLoading = true
        public var isCalendarLoading = false
        public var surface: Surface = .inbox
        public var calendarItems: [CalendarItem] = []
        public var calendarMonthTitle = ""
        public var me: Member?
        public var partner: Member?
        @Presents public var review: ReviewReducer.State?
        public init() {}

        public enum Surface: Equatable, Sendable {
            case inbox, calendar
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
        /// Toast — `ToastClient` → feature `.evenToastHost()`.
        case presentToast(Toast)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case refresh
            case selectDraft(UUID)
            case selectSurface(State.Surface)
        }
    }

    @Dependency(\.draftsClient) var draftsClient
    @Dependency(\.calendarClient) var calendarClient
    @Dependency(\.authClient) var authClient
    @Dependency(\.toastClient) var toastClient
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
                    reminder: review.reminder
                )
                state.review = nil
                return .run { [draftsClient] send in
                    do {
                        _ = try await draftsClient.update(id, body)
                        _ = try await draftsClient.approve(id)
                        await send(.approved(id))
                    } catch {
                        await send(.presentToast(.inboxFailure(error, .approve)))
                    }
                }

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
                    return loadDrafts(surviveStoreTaskCancellation: empty)
                case .calendar:
                    let empty = state.calendarItems.isEmpty
                    if empty { state.isCalendarLoading = true }
                    return loadCalendar(surviveStoreTaskCancellation: empty)
                }

            case let .view(.selectSurface(surface)):
                state.surface = surface
                guard surface == .calendar else { return .none }
                if state.calendarItems.isEmpty {
                    state.isCalendarLoading = true
                }
                return loadCalendar()

            case let .calendarLoaded(response):
                state.isCalendarLoading = false
                state.calendarItems = response.items
                state.calendarMonthTitle = monthTitle(from: response.from)
                return .none

            case let .presentToast(toast):
                if toast.tone == .error {
                    state.isLoading = false
                    state.isCalendarLoading = false
                }
                return toastEffect(toast)
            }
        }
        .ifLet(\.$review, action: \.review) {
            ReviewReducer()
        }
    }

    private enum CancelID { case drafts, calendar }

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

    private func loadCalendar(surviveStoreTaskCancellation: Bool = false) -> Effect<Action> {
        .run { [calendarClient, context, surviveStoreTaskCancellation] send in
            await Self.runFetch(
                surviveStoreTaskCancellation: surviveStoreTaskCancellation,
                context: context,
                send: send,
                fetch: {
                    let cal = Calendar.current
                    let now = Date()
                    let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
                    let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withFullDate]
                    return try await calendarClient.window(
                        f.string(from: start),
                        f.string(from: end)
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

extension Toast {
    enum InboxFailure {
        case load, approve, dismiss, calendar

        var fallback: String {
            switch self {
            case .load: "Couldn’t load inbox"
            case .approve: "Couldn’t approve draft"
            case .dismiss: "Couldn’t dismiss draft"
            case .calendar: "Couldn’t load calendar"
            }
        }
    }

    static func inboxFailure(_ error: Error, _ kind: InboxFailure) -> Toast {
        .failure(from: error, offline: "Couldn’t reach Even", fallback: kind.fallback)
    }
}
