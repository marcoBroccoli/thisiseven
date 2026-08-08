import CalendarClient
import ComposableArchitecture
import DraftsClient
import EvenCore
import GoogleClient

/// Preview / canvas factories. Client closures lag so pull-to-refresh
/// (and other effect paths) show a real spinner in Xcode previews.
public enum InboxPreviewSupport {
    public static let defaultRefreshLag: Duration = .seconds(1)

    public static func populated(
        refreshLag: Duration = defaultRefreshLag
    ) -> StoreOf<InboxReducer> {
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.hasLoadedDrafts = true
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        state.googleConnected = true
        return Store(initialState: state) {
            InboxReducer()
        } withDependencies: {
            let pending = PreviewDelay.delayed(refreshLag) { PreviewData.pendingDrafts }
            let calendar = PreviewDelay.delayed(refreshLag) { PreviewData.calendarMonth }
            $0.draftsClient.pending = pending
            $0.calendarClient.window = { _, _ in try await calendar() }
            $0.googleClient.status = { PreviewData.googleConnected }
        }
    }

    public static func empty(
        refreshLag: Duration = defaultRefreshLag
    ) -> StoreOf<InboxReducer> {
        var state = InboxReducer.State()
        state.isLoading = false
        state.hasLoadedDrafts = true
        state.googleConnected = true
        return Store(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.pending = PreviewDelay.delayed(refreshLag) { [] }
            $0.googleClient.status = { PreviewData.googleConnected }
        }
    }

    /// Seeded skeleton — effects hang so loading chrome stays visible.
    public static func loading() -> StoreOf<InboxReducer> {
        var state = InboxReducer.State()
        state.isLoading = true
        state.googleConnected = true
        return Store(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.pending = PreviewDelay.delayed(.seconds(60)) { PreviewData.pendingDrafts }
            $0.googleClient.status = { PreviewData.googleConnected }
        }
    }

    /// A fetch in flight — the control shows its spinner and the subtitle says
    /// what is happening. The scan never settles, so the state stays visible.
    public static func fetching() -> StoreOf<InboxReducer> {
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts.prefix(2))
        state.hasLoadedDrafts = true
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        state.googleConnected = true
        state.isSyncing = true
        return Store(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.pending = PreviewDelay.delayed(.seconds(60)) { PreviewData.pendingDrafts }
            $0.googleClient.status = { PreviewData.googleSyncing }
            $0.googleClient.startSync = { GoogleSyncStart(started: true) }
        }
    }

    /// No mailbox: the invitation replaces the drafts surface entirely.
    public static func notConnected() -> StoreOf<InboxReducer> {
        var state = InboxReducer.State()
        state.isLoading = false
        state.hasLoadedDrafts = true
        state.googleConnected = false
        return Store(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.pending = { [] }
            $0.googleClient.status = { PreviewData.googleDisconnected }
        }
    }

    public static func calendar(
        refreshLag: Duration = defaultRefreshLag
    ) -> StoreOf<InboxReducer> {
        var state = InboxReducer.State()
        state.surface = .calendar
        state.calendarItems = PreviewData.calendarMonth.items
        state.calendarMonthTitle = "August 2026"
        state.calendarFrom = PreviewData.calendarMonth.from
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        state.googleConnected = true
        return Store(initialState: state) {
            InboxReducer()
        } withDependencies: {
            let calendar = PreviewDelay.delayed(refreshLag) { PreviewData.calendarMonth }
            $0.draftsClient.pending = PreviewDelay.delayed(refreshLag) { [] }
            $0.calendarClient.window = { _, _ in try await calendar() }
            $0.googleClient.status = { PreviewData.googleConnected }
        }
    }

    /// Calendar surface with hanging window fetch — skeleton stays up.
    public static func calendarLoading() -> StoreOf<InboxReducer> {
        var state = InboxReducer.State()
        state.surface = .calendar
        state.isLoading = false
        state.isCalendarLoading = true
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.googleConnected = true
        return Store(initialState: state) {
            InboxReducer()
        } withDependencies: {
            let calendar = PreviewDelay.delayed(.seconds(60)) { PreviewData.calendarMonth }
            $0.calendarClient.window = { _, _ in try await calendar() }
            $0.googleClient.status = { PreviewData.googleConnected }
        }
    }
}
