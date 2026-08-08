import ComposableArchitecture
import EvenCore
import HouseholdClient
@testable import HouseholdsFeature
import ToastClient
import ToastUI
import XCTest

/// One person, several households — and only ever two people in each.
@MainActor
final class HouseholdsFeatureTests: XCTestCase {
    // MARK: Loading

    /// `/v1/me` is resolved with the same header every other request carries —
    /// so whichever household it answers for is the one the checkmark belongs
    /// on, no client-side guessing.
    func testTheOpenHouseholdComesFromTheServersOwnAnswer() async {
        let store = TestStore(initialState: HouseholdsReducer.State()) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.list = { PreviewData.households }
            $0.householdClient.loadProfile = { PreviewData.me }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.appear))
        await store.receive(\.householdsLoaded) {
            $0.isLoading = false
            $0.households = IdentifiedArray(uniqueElements: PreviewData.householdRows)
            $0.invites = [PreviewData.inviteForMe]
            $0.activeHouseholdID = PreviewData.householdId
            $0.myDisplayName = PreviewData.ada.displayName
        }
        XCTAssertTrue(store.state.isActive(PreviewData.atticRow))
        XCTAssertFalse(store.state.isActive(PreviewData.seaHouseRow))
    }

    /// Nothing pinned yet (a fresh install, build 12 behaviour) — the server
    /// falls back to the most recently joined household, which is the last row
    /// `GET /v1/households` returns. The checkmark has to agree.
    func testWithNothingPinnedTheMostRecentlyJoinedHouseholdReadsAsOpen() async {
        let store = TestStore(initialState: HouseholdsReducer.State()) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.list = { PreviewData.households }
            $0.householdClient.loadProfile = { MeResponse(userId: PreviewData.adaId) }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.appear))
        await store.receive(\.householdsLoaded) {
            $0.isLoading = false
            $0.households = IdentifiedArray(uniqueElements: PreviewData.householdRows)
            $0.invites = [PreviewData.inviteForMe]
        }
        XCTAssertTrue(store.state.isActive(PreviewData.seaHouseRow))
        XCTAssertFalse(store.state.isActive(PreviewData.atticRow))
    }

    // MARK: Switching

    func testSwitchingHouseholdsRepointsEveryRequestAndTellsTheApp() async {
        let store = TestStore(initialState: loaded()) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.setActive = { _ in PreviewData.me }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.selectHousehold(PreviewData.seaHouseId))) {
            $0.busyHouseholdID = PreviewData.seaHouseId
        }
        await store.receive(\.switchSucceeded) {
            $0.busyHouseholdID = nil
            $0.expandedHouseholdID = nil
            $0.activeHouseholdID = PreviewData.seaHouseId
        }
        await store.receive(\.delegate.activeHouseholdChanged)
    }

    /// Tapping the household you are already in is not a switch.
    func testTappingTheActiveHouseholdDoesNothing() async {
        let store = TestStore(initialState: loaded()) {
            HouseholdsReducer()
        }

        await store.send(.view(.selectHousehold(PreviewData.householdId)))
    }

    // MARK: Inviting

    func testInvitingAnAddressHoldsTheFreeSeat() async {
        var state = loaded()
        state.expandedHouseholdID = PreviewData.householdId
        state.inviteEmail = " Mira@Example.com "
        state.households[id: PreviewData.householdId]?.memberCount = 1

        let sent = LockIsolated<String?>(nil)
        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.invite = { householdId, email in
                sent.setValue(email)
                return HouseholdInvite(
                    id: UUID(0),
                    householdId: householdId,
                    householdName: "The Attic",
                    invitedByName: "Ada",
                    email: email
                )
            }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.submitInvite(PreviewData.householdId))) {
            $0.busyHouseholdID = PreviewData.householdId
        }
        await store.receive(\.inviteSucceeded) {
            $0.busyHouseholdID = nil
            $0.inviteEmail = ""
            $0.households[id: PreviewData.householdId]?.pendingInviteEmail = "mira@example.com"
        }
        // Trimmed and lowercased before it leaves — matching is case-insensitive
        // on the server, and this keeps the row honest.
        XCTAssertEqual(sent.value, "mira@example.com")
    }

    /// One seat, one live invite — the server says so, and the copy has to say
    /// something a person can act on.
    func testASecondInviteIsRefusedWithCopyYouCanActOn() async {
        var state = loaded()
        state.inviteEmail = "mira@example.com"

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.invite = { _, _ in
                throw APIError.http(status: 409, code: "invite_pending", message: "invite pending")
            }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.submitInvite(PreviewData.householdId))) {
            $0.busyHouseholdID = PreviewData.householdId
        }
        await store.receive(\.inviteFailed) {
            $0.busyHouseholdID = nil
        }
        XCTAssertEqual(
            HouseholdsReducer.inviteCopy(
                for: APIError.http(status: 422, code: "self_invite", message: "")
            ),
            "that’s your own address"
        )
    }

    func testWithdrawingAnInviteFreesTheSeat() async {
        var state = loaded()
        state.households[id: PreviewData.seaHouseId]?.pendingInviteEmail = "mira@example.com"

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.revokeInvite = { _ in }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.revokeInvite(PreviewData.seaHouseId))) {
            $0.busyHouseholdID = PreviewData.seaHouseId
        }
        await store.receive(\.revokeSucceeded) {
            $0.busyHouseholdID = nil
            $0.households[id: PreviewData.seaHouseId]?.pendingInviteEmail = nil
        }
    }

    // MARK: Invites addressed to me

    func testAcceptingAnInviteTakesTheSeatAndOpensThatHousehold() async {
        var state = loaded()
        state.path = .accept
        state.acceptingInvite = PreviewData.inviteForMe
        state.acceptDisplayName = "Ada"

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.acceptInvite = { _, _ in PreviewData.household }
            $0.householdClient.list = { PreviewData.households }
            $0.householdClient.loadProfile = { PreviewData.me }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.submitAccept)) {
            $0.working = true
        }
        await store.receive(\.acceptSucceeded) {
            $0.working = false
            $0.path = .list
            $0.acceptingInvite = nil
            $0.invites = []
            $0.activeHouseholdID = PreviewData.householdId
        }
        await store.receive(\.delegate.activeHouseholdChanged)
        await store.skipReceivedActions(strict: false)
    }

    /// The seat can go while you are deciding. Say so, and re-read the list
    /// instead of leaving a dead card on screen.
    func testAnInviteThatIsGoneSendsYouBackWithAnHonestLine() async {
        var state = loaded()
        state.path = .accept
        state.acceptingInvite = PreviewData.inviteForMe
        state.acceptDisplayName = "Ada"

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.acceptInvite = { _, _ in
                throw APIError.http(status: 404, code: "no_invite", message: "no invite")
            }
            $0.householdClient.list = { HouseholdsResponse(households: PreviewData.householdRows) }
            $0.householdClient.loadProfile = { PreviewData.me }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.submitAccept)) {
            $0.working = true
        }
        await store.receive(\.acceptFailed) {
            $0.working = false
            $0.path = .list
            $0.acceptingInvite = nil
        }
        await store.skipReceivedActions(strict: false)
        XCTAssertEqual(
            HouseholdsReducer.acceptCopy(
                for: APIError.http(status: 404, code: "no_invite", message: "")
            ),
            "that invite is no longer open"
        )
    }

    func testDecliningDropsTheCard() async {
        let store = TestStore(initialState: loaded()) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.declineInvite = { _ in }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.declineTapped(PreviewData.inviteId))) {
            $0.busyInviteID = PreviewData.inviteId
        }
        await store.receive(\.declineSucceeded) {
            $0.busyInviteID = nil
            $0.invites = []
        }
    }

    // MARK: Leaving

    /// Leaving the household on screen has to land somewhere: the app falls to
    /// another one you hold and re-points every request at it.
    func testLeavingTheOpenHouseholdFallsToTheOtherOne() async {
        var state = loaded()
        state.expandedHouseholdID = PreviewData.householdId

        let left = LockIsolated<UUID?>(nil)
        let pinned = LockIsolated<UUID?>(nil)
        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.leave = { id in
                left.setValue(id)
                return LeaveHouseholdResult(ok: true, householdDeleted: false)
            }
            $0.householdClient.setActive = { id in
                pinned.setValue(id)
                return PreviewData.me
            }
            $0.toastClient.show = { _ in }
        }

        // Nothing happens until it is confirmed — the dialog is the guard.
        await store.send(.view(.leaveTapped(PreviewData.householdId))) {
            $0.leavingHousehold = PreviewData.atticRow
        }
        XCTAssertTrue(
            store.state.leaveConfirmationMessage.contains("todos there are archived")
        )
        XCTAssertTrue(
            store.state.leaveConfirmationMessage.contains("Gmail for this household disconnects")
        )
        // Two people in there — leaving does not close the place.
        XCTAssertFalse(store.state.leaveConfirmationMessage.contains("deletes the household"))

        await store.send(.view(.confirmLeave)) {
            $0.leavingHousehold = nil
            $0.busyHouseholdID = PreviewData.householdId
        }
        await store.receive(\.leaveSucceeded) {
            $0.households.remove(id: PreviewData.householdId)
            $0.expandedHouseholdID = nil
            $0.activeHouseholdID = nil
            $0.busyHouseholdID = PreviewData.seaHouseId
        }
        await store.receive(\.switchSucceeded) {
            $0.busyHouseholdID = nil
            $0.activeHouseholdID = PreviewData.seaHouseId
        }
        await store.receive(\.delegate.activeHouseholdChanged)
        XCTAssertEqual(left.value, PreviewData.householdId)
        XCTAssertEqual(pinned.value, PreviewData.seaHouseId)
    }

    /// The last seat: nowhere to fall back to, so the app has to go and set a
    /// household up again. And an only member closing the place should be told.
    func testLeavingTheLastHouseholdSendsTheAppBackToSetup() async {
        var state = HouseholdsReducer.State()
        state.isLoading = false
        state.households = [PreviewData.seaHouseRow]
        state.activeHouseholdID = PreviewData.seaHouseId

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.leave = { _ in
                LeaveHouseholdResult(ok: true, householdDeleted: true)
            }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.leaveTapped(PreviewData.seaHouseId))) {
            $0.leavingHousehold = PreviewData.seaHouseRow
        }
        // One of two — say plainly that this closes the household.
        XCTAssertTrue(store.state.leaveConfirmationMessage.contains("deletes the household"))

        await store.send(.view(.confirmLeave)) {
            $0.leavingHousehold = nil
            $0.busyHouseholdID = PreviewData.seaHouseId
        }
        await store.receive(\.leaveSucceeded) {
            $0.households = []
            $0.busyHouseholdID = nil
            $0.activeHouseholdID = nil
        }
        await store.receive(\.delegate.leftLastHousehold)
    }

    /// Leaving a household you were not looking at leaves the open one alone.
    func testLeavingABackgroundHouseholdDoesNotMoveTheApp() async {
        let store = TestStore(initialState: loaded()) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.leave = { _ in LeaveHouseholdResult() }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.leaveTapped(PreviewData.seaHouseId))) {
            $0.leavingHousehold = PreviewData.seaHouseRow
        }
        await store.send(.view(.confirmLeave)) {
            $0.leavingHousehold = nil
            $0.busyHouseholdID = PreviewData.seaHouseId
        }
        await store.receive(\.leaveSucceeded) {
            $0.households.remove(id: PreviewData.seaHouseId)
            $0.busyHouseholdID = nil
        }
        XCTAssertEqual(store.state.activeHouseholdID, PreviewData.householdId)
    }

    // MARK: Creating another one

    func testCreatingAnotherHouseholdOpensIt() async {
        var state = loaded()
        state.path = .create
        state.newHouseholdName = "  The Cabin  "
        state.newDisplayName = ""
        state.myDisplayName = "Ada"

        let names = LockIsolated<(String, String)?>(nil)
        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.create = { name, display in
                names.setValue((name, display))
                return PreviewData.household
            }
            $0.householdClient.list = { PreviewData.households }
            $0.householdClient.loadProfile = { PreviewData.me }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.submitCreate)) {
            $0.working = true
        }
        await store.receive(\.createSucceeded) {
            $0.working = false
            $0.path = .list
            $0.activeHouseholdID = PreviewData.householdId
        }
        await store.receive(\.delegate.activeHouseholdChanged)
        await store.skipReceivedActions(strict: false)
        // Blank display name falls back to the name you already answer to.
        XCTAssertEqual(names.value?.0, "The Cabin")
        XCTAssertEqual(names.value?.1, "Ada")
    }

    // MARK: Joining with a code

    /// A code is the other way in. Joining opens the household it belongs to —
    /// the same switch the accept-invite flow performs — and the list is pulled
    /// again so the new place has a row.
    func testJoiningWithACodeOpensThatHousehold() async {
        var state = loaded()
        state.path = .join
        state.joinInviteCode = "  k4m2xp  "
        state.joinDisplayName = ""
        state.myDisplayName = "Ada"

        let sent = LockIsolated<(String, String)?>(nil)
        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.join = { code, display in
                sent.setValue((code, display))
                return PreviewData.household
            }
            $0.householdClient.list = { PreviewData.households }
            $0.householdClient.loadProfile = { PreviewData.me }
            $0.toastClient.show = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.view(.submitJoin)) {
            $0.working = true
        }
        await store.receive(\.joinSucceeded) {
            $0.working = false
            $0.path = .list
            $0.joinInviteCode = ""
            $0.activeHouseholdID = PreviewData.householdId
        }
        await store.receive(\.delegate.activeHouseholdChanged)
        // The list is pulled again, so the household just joined has a row.
        await store.receive(\.householdsLoaded) {
            $0.households = IdentifiedArray(uniqueElements: PreviewData.householdRows)
        }
        await store.skipReceivedActions(strict: false)
        // Trimmed + upper-cased on the way out; a blank name falls back to the
        // one this person already answers to.
        XCTAssertEqual(sent.value?.0, "K4M2XP")
        XCTAssertEqual(sent.value?.1, "Ada")
    }

    /// Typing lower case is normal — the field holds what the server looks up.
    func testTheCodeFieldHoldsItsUppercaseShape() async {
        var state = loaded()
        state.path = .join

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        }

        await store.send(.binding(.set(\.joinInviteCode, "k4m2xp"))) {
            $0.joinInviteCode = "K4M2XP"
        }
        XCTAssertTrue(store.state.canSubmitJoin)
    }

    /// A code that opens nothing is a typo, not a failure of the person — and
    /// the form stays put so one character can be fixed.
    func testAWrongCodeKeepsTheFormAndSaysSoKindly() async {
        var state = loaded()
        state.path = .join
        state.joinInviteCode = "XXXXXX"

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.join = { _, _ in
                throw APIError.http(status: 404, code: "bad_code", message: "no household with that code")
            }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.submitJoin)) {
            $0.working = true
        }
        await store.receive(\.joinFailed) {
            $0.working = false
        }
        XCTAssertEqual(store.state.path, .join)
        XCTAssertEqual(store.state.joinInviteCode, "XXXXXX")
        XCTAssertEqual(
            HouseholdsReducer.joinCopy(
                for: APIError.http(status: 404, code: "bad_code", message: "")
            ),
            "that code doesn’t open anything — check it with your partner"
        )
    }

    /// A household holds two people. A third arriving with a real code is told
    /// the seats are gone, not that the code was wrong.
    func testAFullHouseholdRefusesTheCodeWithItsOwnCopy() async {
        var state = loaded()
        state.path = .join
        state.joinInviteCode = "K4M2XP"

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.join = { _, _ in
                throw APIError.http(status: 409, code: "household_full", message: "two people already")
            }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.submitJoin)) {
            $0.working = true
        }
        await store.receive(\.joinFailed) {
            $0.working = false
        }
        XCTAssertEqual(store.state.path, .join)
        XCTAssertEqual(
            HouseholdsReducer.joinCopy(
                for: APIError.http(status: 409, code: "household_full", message: "")
            ),
            "both seats are taken here"
        )
    }

    /// Holding several households is fine; holding the *same* one twice is not.
    func testJoiningAHouseholdYouAreAlreadyInSaysSoPlainly() async {
        var state = loaded()
        state.path = .join
        state.joinInviteCode = "K4M2XP"

        let store = TestStore(initialState: state) {
            HouseholdsReducer()
        } withDependencies: {
            $0.householdClient.join = { _, _ in
                throw APIError.http(status: 409, code: "already_in_household", message: "already a member")
            }
            $0.toastClient.show = { _ in }
        }

        await store.send(.view(.submitJoin)) {
            $0.working = true
        }
        await store.receive(\.joinFailed) {
            $0.working = false
        }
        XCTAssertEqual(store.state.households.count, PreviewData.householdRows.count)
        XCTAssertEqual(
            HouseholdsReducer.joinCopy(
                for: APIError.http(status: 409, code: "already_in_household", message: "")
            ),
            "you’re already in that household"
        )
    }

    /// The form opens on the name you already answer to, with an empty code.
    func testOpeningTheJoinFormOffersTheNameYouAlreadyUse() async {
        let store = TestStore(initialState: loaded()) {
            HouseholdsReducer()
        }

        await store.send(.view(.joinTapped)) {
            $0.path = .join
            $0.joinInviteCode = ""
            $0.joinDisplayName = "Ada"
        }
    }

    // MARK: Helpers

    private func loaded() -> HouseholdsReducer.State {
        var state = HouseholdsReducer.State()
        state.isLoading = false
        state.households = IdentifiedArray(uniqueElements: PreviewData.householdRows)
        state.invites = [PreviewData.inviteForMe]
        state.myDisplayName = "Ada"
        state.activeHouseholdID = PreviewData.householdId
        return state
    }
}
