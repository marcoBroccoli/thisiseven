import ComposableArchitecture
import ConnectionsFeature
import DraftsClient
import EvenApp
import EvenCore
import GoogleClient
import InboxFeature
import ToastClient
import XCTest

/// The seam between the inbox and the one Connections flow: the inbox asks for
/// a connection, and it hears about connects / disconnects that happen there.
@MainActor
final class MainTabGoogleWiringTests: XCTestCase {
    func testInboxConnectRequestOpensProfilesConnections() async {
        let store = TestStore(initialState: MainTabReducer.State()) {
            MainTabReducer()
        } withDependencies: {
            $0.googleClient.connect = {}
            $0.googleClient.status = { PreviewData.googleConnected }
            $0.googleClient.calendarInfo = { PreviewData.calendarInfoCanAdd }
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.inbox(.delegate(.connectGoogleRequested))) {
            $0.tab = .profile
        }
        // Profile forwards it to its own Connections card — the OAuth lives
        // there and nowhere else.
        await store.receive(\.profile.view.connectGoogleTapped)
        await store.skipReceivedActions(strict: false)
    }

    /// Disconnecting flushes that mailbox's drafts on the server; the inbox
    /// must drop its copy instead of showing mail it can no longer refresh.
    func testDisconnectEmptiesTheInbox() async {
        var state = MainTabReducer.State()
        state.inbox.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.inbox.googleConnected = true
        state.inbox.isLoading = false

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.profile(.connections(.disconnectSucceeded)))
        await store.receive(\.inbox.googleConnectionChanged) {
            $0.inbox.googleConnected = false
            $0.inbox.drafts = []
        }
        XCTAssertTrue(store.state.inbox.showsConnectGoogle)
        await store.skipReceivedActions(strict: false)
    }

    func testConnectSucceededTellsTheInbox() async {
        var state = MainTabReducer.State()
        state.inbox.googleConnected = false
        state.inbox.isLoading = false

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.googleClient.calendarInfo = { PreviewData.calendarInfoCanAdd }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.profile(.connections(.connectSucceeded(
            email: "ada@example.com", partnerConnected: false
        ))))
        await store.receive(\.inbox.googleConnectionChanged) {
            $0.inbox.googleConnected = true
        }
        await store.skipReceivedActions(strict: false)
        XCTAssertFalse(store.state.inbox.showsConnectGoogle)
    }
}
