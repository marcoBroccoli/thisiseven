import ComposableArchitecture
import Design
import EvenCore
import GoogleClient
import NotificationsClient

@Reducer
public struct ConnectionsReducer {
    @ObservableState
    public struct State: Equatable {
        public var statusLine = "Not connected"
        public var email: String?
        public var error: String?
        public var working = false
        public init() {}
    }

    public enum Action: ViewAction {
        case view(View)
        case statusLoaded(connected: Bool, email: String?)
        case statusFailed(String)
        case connectSucceeded
        case connectFailed(String)
        case delegate(Delegate)

        @CasePathable
        public enum View: Equatable, Sendable {
            case appear
            case connectTapped
            case skipTapped
        }

        @CasePathable
        public enum Delegate: Equatable {
            case finished
        }
    }

    @Dependency(\.googleClient) var googleClient
    @Dependency(\.notificationsClient) var notificationsClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .view(.appear):
                if EvenLaunchArguments.skipGooglePrompt {
                    return .send(.view(.skipTapped))
                }
                return .run { [googleClient] send in
                    do {
                        let status = try await googleClient.status()
                        await send(.statusLoaded(connected: status.connected, email: status.email))
                    } catch {
                        await send(.statusFailed(String(describing: error)))
                    }
                }
            case let .statusLoaded(connected, email):
                state.statusLine = connected ? "Connected" : "Not connected"
                state.email = email
                return .none
            case let .statusFailed(message):
                state.statusLine = "Status unavailable"
                state.error = message
                return .none
            case .view(.connectTapped):
                state.working = true
                return .run { [googleClient] send in
                    do {
                        try await googleClient.connect()
                        await send(.connectSucceeded)
                    } catch {
                        await send(.connectFailed(String(describing: error)))
                    }
                }
            case .connectSucceeded:
                state.working = false
                state.statusLine = "Connected"
                return finishWithNotificationPrompt()
            case let .connectFailed(message):
                state.working = false
                state.error = message
                return .none
            case .view(.skipTapped):
                return finishWithNotificationPrompt()
            case .delegate:
                return .none
            }
        }
    }

    private func finishWithNotificationPrompt() -> Effect<Action> {
        .run { [notificationsClient] send in
            _ = await notificationsClient.requestAuthorization()
            await send(.delegate(.finished))
        }
    }
}
