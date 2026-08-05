import ComposableArchitecture
import Design
import EvenCore
import GoogleClient
import NotificationsClient
import SwiftUI

@Reducer
public struct ConnectionsFeature {
    @ObservableState
    public struct State: Equatable {
        public var statusLine = "Not connected"
        public var email: String?
        public var error: String?
        public var working = false
        public init() {}
    }

    public enum Action {
        case appear
        case statusLoaded(connected: Bool, email: String?)
        case statusFailed(String)
        case connectTapped
        case connectSucceeded
        case connectFailed(String)
        case skipTapped
        case delegate(Delegate)
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
            case .appear:
                if EvenLaunchArguments.skipGooglePrompt {
                    return .send(.skipTapped)
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
            case .connectTapped:
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
            case .skipTapped:
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

public struct ConnectionsFeatureView: View {
    @Bindable public var store: StoreOf<ConnectionsFeature>

    public init(store: StoreOf<ConnectionsFeature>) {
        self.store = store
    }

    public var body: some View {
        EvenScreenChrome(eyebrow: "Email & Calendar", title: "Connect Gmail\n& Calendar.") {
            Text("Bills become drafts in a shared Approval Inbox. Your partner approves before anything becomes a task.")
                .font(.system(size: 15.5))
                .foregroundStyle(Color(hex: 0x6E6353))
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text(store.statusLine)
                    .font(.system(size: 18, design: .serif))
                if let email = store.email {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(EvenTokens.stone)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EvenTokens.paperCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 28)

            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(EvenTokens.terracotta)
                    .padding(.top, 12)
            }

            Spacer()

            EvenPrimaryButton(store.working ? "Connecting…" : "Connect Google", enabled: !store.working) {
                store.send(.connectTapped)
            }
            Button("Skip for now") { store.send(.skipTapped) }
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(EvenTokens.stone)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .onAppear { store.send(.appear) }
    }
}

#Preview("Connections · disconnected") {
    ConnectionsFeatureView(store: ConnectionsPreviewSupport.disconnected())
}

#Preview("Connections · connected") {
    ConnectionsFeatureView(store: ConnectionsPreviewSupport.connected())
}
