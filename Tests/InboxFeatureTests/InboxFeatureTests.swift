import AuthClient
import ComposableArchitecture
import DraftsClient
import EvenCore
import InboxFeature
import XCTest

@MainActor
final class InboxFeatureTests: XCTestCase {
    func testAppearLoadsPendingDrafts() async {
        let store = TestStore(initialState: InboxFeature.State()) {
            InboxFeature()
        } withDependencies: {
            $0.draftsClient.pending = { PreviewData.pendingDrafts }
            $0.authClient.householdMembers = { (PreviewData.ada, PreviewData.umut) }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off

        await store.send(.appear) {
            $0.isLoading = true
        }
        await store.receive(\.draftsLoaded) {
            $0.isLoading = false
            $0.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        }
        await store.receive(\.membersLoaded) {
            $0.me = PreviewData.ada
            $0.partner = PreviewData.umut
        }
    }

    func testApproveRemovesDraftAndShowsStamp() async {
        var state = InboxFeature.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        let id = PreviewData.pendingDrafts[0].id

        let store = TestStore(initialState: state) {
            InboxFeature()
        } withDependencies: {
            $0.draftsClient.approve = { _ in
                EvenAPIClient.ApproveResponse(
                    draft: PreviewData.pendingDrafts[0],
                    task: PreviewData.waterBill
                )
            }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off

        await store.send(.approve(id))
        await store.receive(\.approved) {
            $0.drafts.remove(id: id)
        }
        await store.receive(\.showStamp) {
            $0.showStamp = true
        }
        await store.receive(\.hideStamp) {
            $0.showStamp = false
        }
    }

    func testSelectDraftPresentsReview() async {
        var state = InboxFeature.State()
        state.drafts = IdentifiedArray(uniqueElements: PreviewData.pendingDrafts)
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        let draft = PreviewData.pendingDrafts[0]

        let store = TestStore(initialState: state) {
            InboxFeature()
        }

        await store.send(.selectDraft(draft.id)) {
            $0.review = InboxFeature.Review.State(
                draft: draft,
                me: PreviewData.ada,
                partner: PreviewData.umut
            )
        }
    }
}
