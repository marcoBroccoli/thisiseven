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
        public var isLoading = false
        public var error: String?
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
        case approve(UUID)
        case dismiss(UUID)
        case approved(UUID)
        case dismissed(UUID)
        case calendarLoaded(CalendarResponse)
        /// Toast — `ToastClient` → feature `.toastHost(.even)`.
        case presentToast(Toast)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case selectDraft(UUID)
            case selectSurface(State.Surface)
        }

        public enum Delegate: Equatable {
            case openToday
        }
    }

    @Dependency(\.draftsClient) var draftsClient
    @Dependency(\.calendarClient) var calendarClient
    @Dependency(\.authClient) var authClient
    @Dependency(\.toastClient) var toastClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appear):
                state.isLoading = true
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

            case let .approve(id):
                return .run { [draftsClient] send in
                    do {
                        _ = try await draftsClient.approve(id)
                        await send(.approved(id))
                    } catch {
                        await send(.presentToast(.inboxFailure(error, .approve)))
                    }
                }

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

            case let .view(.selectSurface(surface)):
                state.surface = surface
                guard surface == .calendar else { return .none }
                return loadCalendar()

            case let .calendarLoaded(response):
                state.calendarItems = response.items
                state.calendarMonthTitle = monthTitle(from: response.from)
                return .none

            case let .presentToast(toast):
                if toast.tone == .error {
                    state.isLoading = false
                    state.error = toast.message
                }
                return toastEffect(toast)

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$review, action: \.review) {
            ReviewReducer()
        }
    }

    private func loadDrafts() -> Effect<Action> {
        .run { [draftsClient] send in
            do {
                try await send(.draftsLoaded(await draftsClient.pending()))
            } catch {
                await send(.presentToast(.inboxFailure(error, .load)))
            }
        }
    }

    private func loadCalendar() -> Effect<Action> {
        .run { [calendarClient] send in
            let cal = Calendar.current
            let now = Date()
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            do {
                let response = try await calendarClient.window(f.string(from: start), f.string(from: end))
                await send(.calendarLoaded(response))
            } catch {
                await send(.presentToast(.inboxFailure(error, .calendar)))
            }
        }
    }

    private func toastEffect(_ toast: Toast) -> Effect<Action> {
        .run { [toastClient] _ in
            await toastClient.show(toast)
        }
    }

    private func monthTitle(from iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: iso) else { return iso }
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
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
