import AuthClient
import ComposableArchitecture
import DraftsClient
import EvenApp
import EvenCore
import GoogleClient
import HouseholdClient
import HouseholdRealtimeClient
import HouseholdsFeature
import InboxFeature
import ProfileFeature
import SummaryClient
import ToastClient
import TodayFeature
import WidgetClient
import XCTest

/// Nothing crosses between households. When the app starts looking at another
/// one, every household-scoped surface has to be pulled again — and the socket,
/// which carries the id in its URL, has to be dialled again too.
@MainActor
final class MainTabHouseholdSwitchTests: XCTestCase {
    func testSwitchingHouseholdsEmptiesTheTabsAndRedialsTheSocket() async {
        var state = MainTabReducer.State()
        state.inbox.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.inbox.isLoading = false
        state.today.summary = PreviewData.summary

        let connections = LockIsolated(0)
        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.householdRealtimeClient.events = {
                connections.withValue { $0 += 1 }
                return AsyncStream { $0.finish() }
            }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.googleClient.status = { PreviewData.googleDisconnected }
            $0.googleClient.calendarInfo = { PreviewData.calendarInfoCanAdd }
            $0.widgetClient.publish = { _ in }
            $0.toastClient.show = { _ in }
            $0.date.now = Date(timeIntervalSince1970: 1_754_640_000)
            $0.calendar = Calendar(identifier: .gregorian)
        }
        store.exhaustivity = .off

        await store.send(.profile(.delegate(.activeHouseholdChanged(PreviewData.seaHouseId)))) {
            $0.today = TodayReducer.State()
            $0.inbox = InboxReducer.State()
        }
        // Another house's week must not linger on screen behind the refetch.
        XCTAssertNil(store.state.today.summary)
        XCTAssertTrue(store.state.inbox.drafts.isEmpty)

        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(connections.value, 1)
        await store.finish()
    }

    /// Profile is only the messenger — the switch happens on the households
    /// screen it pushes, and the delegate has to reach the app shell.
    func testTheHouseholdsScreenBubblesTheSwitchThroughProfile() async {
        var profile = ProfileReducer.State()
        profile.households = HouseholdsReducer.State()

        let store = TestStore(initialState: profile) {
            ProfileReducer()
        } withDependencies: {
            $0.householdClient.loadProfile = { PreviewData.me }
            $0.householdClient.list = { PreviewData.households }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.households(.presented(.delegate(
            .activeHouseholdChanged(PreviewData.seaHouseId)
        ))))
        await store.receive(\.delegate.activeHouseholdChanged)
        await store.skipReceivedActions(strict: false)
    }
}
