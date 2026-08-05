import ComposableArchitecture
import ConnectionsFeature
import EvenCore
import GoogleClient
import NotificationsClient
import XCTest

@MainActor
final class ConnectionsFeatureTests: XCTestCase {
    func testSkipFinishesAfterNotificationPrompt() async {
        let store = TestStore(initialState: ConnectionsFeature.State()) {
            ConnectionsFeature()
        } withDependencies: {
            $0.notificationsClient.requestAuthorization = { true }
        }

        await store.send(.skipTapped)
        await store.receive(\.delegate.finished)
    }

    func testConnectSuccessFinishes() async {
        let store = TestStore(initialState: ConnectionsFeature.State()) {
            ConnectionsFeature()
        } withDependencies: {
            $0.googleClient.connect = {}
            $0.notificationsClient.requestAuthorization = { true }
        }

        await store.send(.connectTapped) {
            $0.working = true
        }
        await store.receive(\.connectSucceeded) {
            $0.working = false
            $0.statusLine = "Connected"
        }
        await store.receive(\.delegate.finished)
    }
}
