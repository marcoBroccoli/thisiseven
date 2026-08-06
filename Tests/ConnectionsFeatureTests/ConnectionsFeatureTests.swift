import ComposableArchitecture
import ConnectionsFeature
import Design
import EvenCore
import Foundation
import GoogleClient
import NotificationsClient
import ToastClient
import XCTest

@MainActor
final class ConnectionsFeatureTests: XCTestCase {
    func testSkipFinishesAfterNotificationPrompt() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.notificationsClient.requestAuthorization = { true }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.secondaryTapped))
        await store.receive(\.delegate.finished)
    }

    func testAppearChecksStatus() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.status = { PreviewData.googleDisconnected }
        }

        await store.send(.view(.appear)) {
            $0.isCheckingStatus = true
        }
        await store.receive(\.statusLoaded) {
            $0.isCheckingStatus = false
        }
    }

    func testAppearAlreadyConnectedJumpsToConnected() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.status = { PreviewData.googleConnected }
        }

        await store.send(.view(.appear)) {
            $0.isCheckingStatus = true
        }
        await store.receive(\.statusLoaded) {
            $0.isCheckingStatus = false
            $0.email = PreviewData.googleConnected.email
            $0.path = .connected
        }
    }

    func testConnectAdvancesToScopes() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.connect = {}
            $0.googleClient.status = { PreviewData.googleConnected }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.primaryTapped)) {
            $0.working = true
        }
        await store.receive(\.connectSucceeded) {
            $0.working = false
            $0.email = PreviewData.googleConnected.email
            $0.path = .scopes
        }
    }

    func testConnectFailurePresentsErrorToast() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.connect = { throw URLError(.notConnectedToInternet) }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.primaryTapped)) {
            $0.working = true
        }
        await store.receive(\.presentToast) {
            $0.working = false
            $0.isCheckingStatus = false
        }
    }

    func testConnectCancelIsQuiet() async {
        let store = TestStore(initialState: ConnectionsReducer.State()) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.connect = { throw CancellationError() }
        }

        await store.send(.view(.primaryTapped)) {
            $0.working = true
        }
        await store.receive(\.connectCancelled) {
            $0.working = false
        }
    }

    func testAllowScopesThenGoToEvenFinishes() async {
        var state = ConnectionsReducer.State()
        state.path = .scopes
        state.email = PreviewData.googleConnected.email

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.notificationsClient.requestAuthorization = { true }
        }

        await store.send(.view(.primaryTapped)) {
            $0.path = .connected
        }
        await store.send(.view(.primaryTapped))
        await store.receive(\.delegate.finished)
    }

    func testDisconnectReturnsToWhy() async {
        var state = ConnectionsReducer.State()
        state.path = .connected
        state.email = PreviewData.googleConnected.email

        let store = TestStore(initialState: state) {
            ConnectionsReducer()
        } withDependencies: {
            $0.googleClient.disconnect = {}
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.disconnectTapped)) {
            $0.working = true
        }
        await store.receive(\.disconnectSucceeded) {
            $0.working = false
            $0.email = nil
            $0.path = .why
        }
    }
}
