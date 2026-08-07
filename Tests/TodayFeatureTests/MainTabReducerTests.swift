import AuthClient
import ComposableArchitecture
import EvenApp
import EvenCore
import HouseholdRealtimeClient
import SummaryClient
import WidgetClient
import XCTest

@MainActor
final class MainTabReducerTests: XCTestCase {
    func testRealtimeSummaryInvalidateRefreshesToday() async {
        let (stream, continuation) = AsyncStream.makeStream(of: HouseholdRealtimeEvent.self)
        var state = MainTabReducer.State()
        state.today.me = PreviewData.ada
        state.today.summary = PreviewData.summary
        state.today.isLoading = false

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.householdRealtimeClient.events = { stream }
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.widgetClient.publish = { _ in }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        continuation.yield(
            HouseholdRealtimeEvent(
                scopes: ["summary"],
                reason: "task_toggled",
                actorMemberId: PreviewData.umut.id
            )
        )
        await store.receive(\.realtime)
        await store.receive(\.today.view.refresh)
        await store.receive(\.today.summaryLoaded)
        continuation.finish()
        await store.finish()
    }

    func testRealtimeFromSelfSkipsTodayRefresh() async {
        let (stream, continuation) = AsyncStream.makeStream(of: HouseholdRealtimeEvent.self)
        var state = MainTabReducer.State()
        state.today.me = PreviewData.ada
        state.today.summary = PreviewData.summary
        state.today.isLoading = false
        let fetched = LockIsolated(0)

        let store = TestStore(initialState: state) {
            MainTabReducer()
        } withDependencies: {
            $0.householdRealtimeClient.events = { stream }
            $0.summaryClient.fetch = {
                fetched.withValue { $0 += 1 }
                return PreviewData.summary
            }
            $0.widgetClient.publish = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        continuation.yield(
            HouseholdRealtimeEvent(
                scopes: ["summary"],
                reason: "task_toggled",
                actorMemberId: PreviewData.ada.id
            )
        )
        await store.receive(\.realtime)
        continuation.finish()
        await store.finish()
        XCTAssertEqual(fetched.value, 0)
    }

    func testSelectProfileTab() async {
        let store = TestStore(initialState: MainTabReducer.State()) {
            MainTabReducer()
        }
        await store.send(.view(.selectTab(.profile))) {
            $0.tab = .profile
        }
    }
}
