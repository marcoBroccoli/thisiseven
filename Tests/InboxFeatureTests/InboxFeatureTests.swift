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
            $0.hasLoadedDrafts = true
            $0.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        }
        // Members load is merged with drafts — either action may land first.
        // Non-exhaustive receive of drafts may have already skipped members.
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(store.state.me, PreviewData.ada)
        XCTAssertEqual(store.state.partner, PreviewData.umut)
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
            $0.hasLoadedDrafts = true
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

        await store.send(.view(.refresh)) {
            $0.isLoading = true
        }
        await store.receive(\.draftsLoaded) {
            $0.isLoading = false
            $0.hasLoadedDrafts = true
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

    // MARK: - Swipe actions

    /// Swipe-approve must be the *same* two calls the review sheet makes —
    /// patch then approve — only with the draft's own values.
    func testSwipeApproveUsesSameClientCallsAsReview() async {
        let draft = PreviewData.pendingDrafts[0]
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        let patched = LockIsolated<(UUID, EvenAPIClient.DraftPatchBody)?>(nil)
        let approved = LockIsolated<UUID?>(nil)
        let toasted = LockIsolated<String?>(nil)

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.update = { id, body in
                patched.setValue((id, body))
                return draft
            }
            $0.draftsClient.approve = { id in
                approved.setValue(id)
                return EvenAPIClient.ApproveResponse(draft: draft, task: PreviewData.waterBill)
            }
            $0.toastClient.show = { toasted.setValue($0.message) }
        }
        store.exhaustivity = .off

        await store.send(.view(.approveDraft(draft.id)))
        await store.receive(\.approved) {
            $0.drafts.remove(id: draft.id)
        }

        XCTAssertEqual(patched.value?.0, draft.id)
        XCTAssertEqual(patched.value?.1.title, draft.title)
        XCTAssertEqual(patched.value?.1.ownerMemberId, draft.ownerMemberId)
        XCTAssertEqual(patched.value?.1.dueOn, draft.dueOn)
        XCTAssertEqual(patched.value?.1.reminder, draft.reminder)
        XCTAssertEqual(approved.value, draft.id)
        XCTAssertEqual(toasted.value, "Approved → task + calendar event")
    }

    func testSwipeApproveFailureToastsAndKeepsDraft() async {
        let draft = PreviewData.pendingDrafts[0]
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        let toasted = LockIsolated<Toast.Tone?>(nil)

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.update = { _, _ in throw URLError(.timedOut) }
            $0.toastClient.show = { toasted.setValue($0.tone) }
        }
        store.exhaustivity = .off

        await store.send(.view(.approveDraft(draft.id)))
        await store.receive(\.presentToast)
        XCTAssertEqual(toasted.value, .error)
        XCTAssertNotNil(store.state.drafts[id: draft.id])
    }

    func testSwipeApproveUnknownDraftIsANoOp() async {
        let store = TestStore(initialState: InboxReducer.State()) {
            InboxReducer()
        }
        await store.send(.view(.approveDraft(UUID())))
    }

    func testSwipeDismissRemovesDraft() async {
        let draft = PreviewData.pendingDrafts[1]
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        let dismissed = LockIsolated<UUID?>(nil)

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.dismiss = { id in
                dismissed.setValue(id)
                return draft
            }
        }
        store.exhaustivity = .off

        await store.send(.view(.dismissDraft(draft.id)))
        await store.receive(\.dismiss)
        await store.receive(\.dismissed) {
            $0.drafts.remove(id: draft.id)
        }
        XCTAssertEqual(dismissed.value, draft.id)
    }

    func testSwipeDismissUnknownDraftIsANoOp() async {
        let store = TestStore(initialState: InboxReducer.State()) {
            InboxReducer()
        }
        await store.send(.view(.dismissDraft(UUID())))
    }

    // MARK: - Review sheet — due date

    func testReviewDueDateEditIsSentOnApprove() async {
        let draft = PreviewData.pendingDrafts[0]
        var state = InboxReducer.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.review = ReviewReducer.State(draft: draft, me: PreviewData.ada, partner: PreviewData.umut)
        let patched = LockIsolated<EvenAPIClient.DraftPatchBody?>(nil)
        let picked = Date(timeIntervalSince1970: 1_786_233_600) // 2026-08-15 (UTC noonless)

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.draftsClient.update = { _, body in
                patched.setValue(body)
                return draft
            }
            $0.draftsClient.approve = { _ in
                EvenAPIClient.ApproveResponse(draft: draft, task: PreviewData.waterBill)
            }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.review(.presented(.view(.setDueDate(picked)))))
        let edited = store.state.review?.dueOn
        XCTAssertNotEqual(edited, draft.dueOn)
        XCTAssertEqual(store.state.review?.dueOnEdited, true)

        await store.send(.review(.presented(.view(.approveTapped)))) {
            $0.review = nil
        }
        await store.receive(\.approved)
        XCTAssertEqual(patched.value?.dueOn, edited)
    }

    /// A Gmail draft's `due_on` can only have come from the extractor — that is
    /// the whole basis for the "detected from the email" caption.
    func testDetectedDueDateProvenance() {
        let gmailDraft = PreviewData.pendingDrafts[0]
        let detected = ReviewReducer.State(draft: gmailDraft, me: nil, partner: nil)
        XCTAssertTrue(detected.dueOnWasDetected)
        XCTAssertFalse(detected.dueOnEdited)
        XCTAssertEqual(detected.detectedDueOn, gmailDraft.dueOn)

        var manual = gmailDraft
        manual.gmail = false
        XCTAssertFalse(ReviewReducer.State(draft: manual, me: nil, partner: nil).dueOnWasDetected)

        var undated = gmailDraft
        undated.dueOn = nil
        let none = ReviewReducer.State(draft: undated, me: nil, partner: nil)
        XCTAssertFalse(none.dueOnWasDetected)
        XCTAssertNil(none.dueOn)
    }

    // MARK: - Calendar surface

    func testCalendarLayoutAndDayFilter() async {
        var state = InboxReducer.State()
        state.surface = .calendar
        state.isLoading = false
        state.calendarItems = PreviewData.calendarMonth.items

        let store = TestStore(initialState: state) {
            InboxReducer()
        }

        await store.send(.view(.selectCalendarLayout(.agenda))) {
            $0.calendarLayout = .agenda
        }
        await store.send(.view(.selectCalendarDay("2026-08-08"))) {
            $0.selectedCalendarDay = "2026-08-08"
        }
        // Tapping the same day clears the filter — the grid filters, not modes.
        await store.send(.view(.selectCalendarDay("2026-08-08"))) {
            $0.selectedCalendarDay = nil
        }
    }

    func testStepMonthReloadsWindowAndClearsSelection() async {
        var state = InboxReducer.State()
        state.surface = .calendar
        state.isLoading = false
        state.calendarItems = PreviewData.calendarMonth.items
        state.selectedCalendarDay = "2026-08-08"

        let store = TestStore(initialState: state) {
            InboxReducer()
        } withDependencies: {
            $0.calendarClient.window = { _, _ in PreviewData.calendarMonth }
        }
        store.exhaustivity = .off

        await store.send(.view(.stepCalendarMonth(1))) {
            $0.calendarMonthOffset = 1
            $0.selectedCalendarDay = nil
            $0.calendarItems = []
            $0.isCalendarLoading = true
        }
        await store.receive(\.calendarLoaded) {
            $0.isCalendarLoading = false
            $0.calendarItems = PreviewData.calendarMonth.items
            $0.calendarFrom = PreviewData.calendarMonth.from
            $0.calendarMonthTitle = "August 2026"
        }
    }

    func testCalendarLoadedKeepsGridAnchor() async {
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
            $0.calendarFrom = "2026-08-01"
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
