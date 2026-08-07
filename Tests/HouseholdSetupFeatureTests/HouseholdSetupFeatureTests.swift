import ComposableArchitecture
import EvenCore
import HouseholdClient
import HouseholdSetupFeature
import XCTest

@MainActor
final class HouseholdSetupFeatureTests: XCTestCase {
    func testCreatePathSucceedsAndRevealsInvite() async {
        var state = HouseholdSetupReducer.State()
        state.path = .create
        state.name = "The Attic"
        let store = TestStore(initialState: state) {
            HouseholdSetupReducer()
        } withDependencies: {
            $0.householdClient.create = { _, _ in PreviewData.household }
        }

        await store.send(.view(.submitCreate)) {
            $0.working = true
        }
        await store.receive(\.createSucceeded) {
            $0.working = false
            $0.inviteReveal = PreviewData.household.inviteCode
            $0.path = .inviteReveal
        }
    }

    func testBackFromCreateReturnsToChoice() async {
        var state = HouseholdSetupReducer.State()
        state.path = .create
        state.error = "stale"
        let store = TestStore(initialState: state) {
            HouseholdSetupReducer()
        }

        await store.send(.view(.backTapped)) {
            $0.path = .choice
            $0.error = nil
        }
    }

    func testJoinFailureSurfacesError() async {
        struct Boom: Error {}
        var state = HouseholdSetupReducer.State()
        state.path = .join
        state.inviteCode = "BAD"
        let store = TestStore(initialState: state) {
            HouseholdSetupReducer()
        } withDependencies: {
            $0.householdClient.join = { _, _ in throw Boom() }
        }

        await store.send(.view(.submitJoin)) {
            $0.working = true
        }
        await store.receive(\.joinFailed) {
            $0.working = false
            $0.error = String(describing: Boom())
        }
    }
}
