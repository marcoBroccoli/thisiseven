import AuthClient
import CalendarClient
import ComposableArchitecture
import DraftsClient
import EvenCore

public enum InboxPreviewSupport {
    public static func populated() -> StoreOf<InboxFeature> {
        var state = InboxFeature.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            InboxFeature()
        } withDependencies: {
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.draftsClient.update = { id, _ in
                PreviewData.pendingDrafts.first { $0.id == id } ?? PreviewData.pendingDrafts[0]
            }
            $0.draftsClient.approve = { _ in
                EvenAPIClient.ApproveResponse(
                    draft: PreviewData.pendingDrafts[0],
                    task: PreviewData.waterBill
                )
            }
            $0.draftsClient.dismiss = { id in
                PreviewData.pendingDrafts.first { $0.id == id } ?? PreviewData.pendingDrafts[0]
            }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            $0.calendarClient.window = { _, _ in PreviewData.calendarMonth }
        }
    }

    public static func empty() -> StoreOf<InboxFeature> {
        var state = InboxFeature.State()
        state.isLoading = false
        return Store(initialState: state) {
            InboxFeature()
        } withDependencies: {
            $0.draftsClient.pending = { [] }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
        }
    }

    public static func calendar() -> StoreOf<InboxFeature> {
        var state = InboxFeature.State()
        state.surface = .calendar
        state.calendarItems = PreviewData.calendarMonth.items
        state.calendarMonthTitle = "August 2026"
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.isLoading = false
        return Store(initialState: state) {
            InboxFeature()
        } withDependencies: {
            $0.draftsClient.pending = { [] }
            $0.calendarClient.window = { _, _ in PreviewData.calendarMonth }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
        }
    }
}
