import AuthClient
import ComposableArchitecture
import EvenCore
import SummaryClient
import TasksClient
import TodayReducer
import WidgetClient
import XCTest

@MainActor
final class TodayFeatureTests: XCTestCase {
    func testAppearLoadsSummaryAndMembers() async {
        let store = TestStore(initialState: TodayReducer.State()) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            $0.widgetClient.publish = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear)) {
            $0.isLoading = true
        }
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.summary = PreviewData.summary
        }
        await store.receive(\.membersLoaded) {
            $0.me = PreviewData.ada
            $0.partner = PreviewData.umut
        }
    }

    func testToggleRefreshesSummary() async {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        let id = PreviewData.laundry.id

        let store = TestStore(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.tasksClient.toggle = { _ in PreviewData.laundry }
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            $0.widgetClient.publish = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.toggle(id)))
        await store.receive(\.view.appear) {
            $0.isLoading = true
        }
        await store.receive(\.summaryLoaded) {
            $0.isLoading = false
            $0.summary = PreviewData.summary
        }
    }
}
