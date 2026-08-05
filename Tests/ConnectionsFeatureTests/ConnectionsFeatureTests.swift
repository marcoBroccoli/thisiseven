import ComposableArchitecture
import ConnectionsReducer
import EvenCore
import GoogleClient
import NotificationsClient
import XCTest

@MainActor
final class ConnectionsFeatureTests: XCTestCase {
    func testSkipFinishesAfterNotificationPrompt() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.notificationsClient.requestAuthorization = { true }
        }

        await store.send(.view(.skipTapped))
        await store.receive(\.delegate.finished)
    }

    func testConnectSuccessFinishes() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.connect = {}
            $0.notificationsClient.requestAuthorization = { true }
        }

        await store.send(.view(.connectTapped)) {
            $0.working = true
        }
        await store.receive(\.connectSucceeded) {
            $0.working = false
            $0.statusLine = "Connected"
        }
        await store.receive(\.delegate.finished)
    }
}
