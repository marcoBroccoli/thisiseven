import AuthClient
import ComposableArchitecture
import EvenCore
import SummaryClient
import TasksClient
import WidgetClient

public enum TodayPreviewSupport {
    public static func populated() -> StoreOf<TodayFeature> {
        var state = TodayFeature.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            TodayFeature()
        } withDependencies: {
            $0.summaryClient.fetch = { PreviewData.summary }
            $0.tasksClient.toggle = { _ in PreviewData.laundry }
            $0.tasksClient.create = { _ in PreviewData.laundry }
            $0.widgetClient.publish = { _ in }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
        }
    }

    public static func empty() -> StoreOf<TodayFeature> {
        var state = TodayFeature.State()
        state.summary = PreviewData.summaryEmpty
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            TodayFeature()
        } withDependencies: {
            $0.summaryClient.fetch = { PreviewData.summaryEmpty }
            $0.widgetClient.publish = { _ in }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
        }
    }

    public static func loading() -> StoreOf<TodayFeature> {
        var state = TodayFeature.State()
        state.isLoading = true
        return Store(initialState: state) {
            TodayFeature()
        } withDependencies: {
            $0.summaryClient.fetch = {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return PreviewData.summary
            }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
        }
    }
}
