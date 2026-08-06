import AuthClient
import CalendarClient
import ComposableArchitecture
import DraftsClient
import EvenCore
import InboxFeature
import ToastClient
import ToastUI
import XCTest

@MainActor
final class InboxFeatureTests: XCTestCase {
    func testAppearLoadsPendingDrafts() async {
        let store = TestStore(initialState: InboxReducer.State()) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        await store.receive(\.draftsLoaded) {
            $0.isLoading = false
            $0.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        }
        await store.receive(\.membersLoaded) {
            $0.me = PreviewData.ada
            $0.partner = PreviewData.umut
        }
    }

    func testAppearWithExistingDraftsDoesNotFlashLoading() async {
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.isLoading = false

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        await store.receive(\.draftsLoaded) {
            $0.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        }
        XCTAssertFalse(store.state.isLoading)
    }

    func testReviewApproveRemovesDraftAndToasts() async {
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        let draft = PreviewData.pendingDrafts[0]
        state.review = ReviewReducer.State(
            draft: draft,
            me: PreviewData.ada,
            partner: PreviewData.umut
        )
        let toasted = LockIsolated<String?>(nil)

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.update = { id, _ in
                PreviewData.pendingDrafts.first { $0.id == id } ?? draft
            }
            $0.draftsClient.approve = { _ in
                EvenAPIClient.ApproveResponse(draft: draft, task: PreviewData.waterBill)
            }
            $0.toastClient.show = { toast in
                toasted.setValue(toast.message)
            }
        }
        store.exhaustivity = .off

        await store.send(.review(.presented(.view(.approveTapped)))) {
            $0.review = nil
        }
        await store.receive(\.approved) {
            $0.drafts.remove(id: draft.id)
        }
        XCTAssertEqual(toasted.value, "Approved → task + calendar event")
    }

    func testSelectDraftPresentsReview() async {
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        let draft = PreviewData.pendingDrafts[0]

        let store = TestStore(initialState: state) {
            InboxReducer()
        }

        await store.send(.view(.selectDraft(draft.id))) {
            $0.review = ReviewReducer.State(
                draft: draft,
                me: PreviewData.ada,
                partner: PreviewData.umut
            )
        }
    }

    func testRefreshReloadsPendingDrafts() async {
        var state = InboxReducer.State()
        state.surface = .inbox
        state.isLoading = false
        state.drafts = []

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
        }
        store.exhaustivity = .off

        await store.send(.view(.refresh))
        await store.receive(\.draftsLoaded) {
            $0.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        }
    }

    func testSelectCalendarSurfaceLoadsWindow() async {
        var state = InboxReducer.State()
        state.isLoading = false

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.calendarClient.window = { _, _ in PreviewData.calendarMonth }
        }
        store.exhaustivity = .off

        await store.send(.view(.selectSurface(.calendar))) {
            $0.surface = .calendar
            $0.isCalendarLoading = true
        }
        await store.receive(\.calendarLoaded) {
            $0.isCalendarLoading = false
            $0.calendarItems = PreviewData.calendarMonth.items
            $0.calendarMonthTitle = "August 2026"
        }
    }

    func testRefreshCalendarWhenEmptyShowsLoading() async {
        var state = InboxReducer.State()
        state.surface = .calendar
        state.isLoading = false
        state.calendarItems = []

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.calendarClient.window = { _, _ in PreviewData.calendarMonth }
        }
        store.exhaustivity = .off

        await store.send(.view(.refresh)) {
            $0.isCalendarLoading = true
        }
        await store.receive(\.calendarLoaded) {
            $0.isCalendarLoading = false
            $0.calendarItems = PreviewData.calendarMonth.items
            $0.calendarMonthTitle = "August 2026"
        }
    }

    func testLoadFailureClearsLoadingAndToasts() async {
        let toasted = LockIsolated<Toast.Tone?>(nil)

        let store = TestStore(initialState: InboxReducer.State()) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.pending = { throw URLError(.notConnectedToInternet) }
            $0.authClient.householdMembers = { (nil, nil) }
            $0.toastClient.show = { toast in
                toasted.setValue(toast.tone)
            }
        }
        store.exhaustivity = .off

        await store.send(.view(.appear))
        await store.receive(\.presentToast) {
            $0.isLoading = false
        }
        XCTAssertEqual(toasted.value, .error)
    }
}
