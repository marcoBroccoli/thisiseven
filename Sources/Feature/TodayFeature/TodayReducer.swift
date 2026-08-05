import AuthClient
import ComposableArchitecture
import EvenCore
import Foundation
import SummaryClient
import TasksClient
import WidgetClient

@Reducer
public struct TodayReducer {
    @ObservableState
    public struct State: Equatable {
        public var summary: Summary?
        public var me: Member?
        public var partner: Member?
        public var error: String?
        public var isLoading = false
        @Presents public var composer: ComposerReducer.State?
        public init() {}
    }

    public enum Action: ViewAction {
        case view(View)
        case membersLoaded(Member?, Member?)
        case summaryLoaded(Summary)
        case loadFailed(String)
        case toggleFailed(String)
        case composer(PresentationAction<ComposerReducer.Action>)
        case createTask
        case createFailed(String)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case toggle(UUID)
            case addTapped
        }

        public enum Delegate: Equatable {
            case openInbox
        }
    }

    @Dependency(\.summaryClient) var summaryClient
    @Dependency(\.tasksClient) var tasksClient
    @Dependency(\.widgetClient) var widgetClient
    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appear):
                state.isLoading = true
                return .merge(
                    refresh(),
                    .run { [authClient] send in
                        let members = await authClient.householdMembers()
                        await send(.membersLoaded(members.me, members.partner))
                    }
                )

            case let .membersLoaded(me, partner):
                state.me = me
                state.partner = partner
                return .none

            case let .summaryLoaded(summary):
                state.isLoading = false
                state.summary = summary
                return publishWidget(summary)

            case let .loadFailed(message):
                state.isLoading = false
                state.error = message
                return .none

            case let .view(.toggle(id)):
                return .run { [tasksClient] send in
                    do {
                        _ = try await tasksClient.toggle(id)
                        await send(.view(.appear))
                    } catch {
                        await send(.toggleFailed(String(describing: error)))
                    }
                }

            case let .toggleFailed(message):
                state.error = message
                return .none

            case .view(.addTapped):
                state.composer = ComposerReducer.State()
                return .none

            case .composer(.presented(.view(.saveTapped))):
                return .send(.createTask)

            case .composer(.presented(.view(.cancelTapped))):
                state.composer = nil
                return .none

            case .composer:
                return .none

            case .createTask:
                guard let composer = state.composer else { return .none }
                let owner = composer.ownerIsMe
                    ? (state.me?.id ?? state.summary?.pebbles.first?.memberId)
                    : (state.partner?.id ?? state.summary?.pebbles.dropFirst().first?.memberId)
                guard let owner else { return .none }
                let body = EvenAPIClient.TaskDraftBody(
                    title: composer.title,
                    section: .chore,
                    ownerMemberId: owner,
                    weight: composer.weight,
                    recurrence: .none,
                    dueOn: nil
                )
                state.composer = nil
                return .run { [tasksClient] send in
                    do {
                        _ = try await tasksClient.create(body)
                        await send(.view(.appear))
                    } catch {
                        await send(.createFailed(String(describing: error)))
                    }
                }

            case let .createFailed(message):
                state.error = message
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$composer, action: \.composer) {
            ComposerReducer()
        }
    }

    private func refresh() -> Effect<Action> {
        .run { [summaryClient] send in
            do {
                try await send(.summaryLoaded(await summaryClient.fetch()))
            } catch {
                await send(.loadFailed(String(describing: error)))
            }
        }
    }

    private func publishWidget(_ summary: Summary) -> Effect<Action> {
        .run { [widgetClient] _ in
            let snap = EvenWidgetSnapshot(
                weekIndex: summary.week.index,
                clay: .init(
                    name: "A", initial: "A", color: .clay,
                    share: summary.percentMe, done: 0
                ),
                teal: .init(
                    name: "B", initial: "B", color: .teal,
                    share: summary.percentPartner, done: 0
                ),
                hasPartner: true,
                leader: summary.caption,
                leftToday: summary.sections.flatMap(\.tasks).filter { !$0.done }.count,
                upcoming: [],
                generatedAt: .now
            )
            await widgetClient.publish(snap)
        }
    }
}
