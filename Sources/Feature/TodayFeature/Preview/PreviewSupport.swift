import ComposableArchitecture
import EvenCore
import SummaryClient

public enum TodayPreviewSupport {
    public static let defaultLoadLag: Duration = .seconds(10)

    public static func populated() -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.summary = PreviewData.summary
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            TodayReducer()
        }
    }

    public static func empty() -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.summary = PreviewData.summaryEmpty
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = { PreviewData.summaryEmpty }
        }
    }

    public static func loading(
        loadLag: Duration = defaultLoadLag
    ) -> StoreOf<TodayReducer> {
        var state = TodayReducer.State()
        state.isLoading = true
        return Store(initialState: state) {
            TodayReducer()
        } withDependencies: {
            $0.summaryClient.fetch = PreviewDelay.delayed(loadLag) { PreviewData.summary }
        }
    }
}
