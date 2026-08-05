import ComposableArchitecture
import EvenCore
import HouseholdClient
import HouseholdSetupFeature
import XCTest

@MainActor
final class HouseholdSetupFeatureTests: XCTestCase {
    func testCreatePathSucceedsAndRevealsInvite() async {
        var state = HouseholdSetupFeature.State()
        state.path = .create
        state.name = "The Attic"
        let store = TestStore(initialState: state) {
            HouseholdSetupFeature()
        } withDependencies: {
            $0.householdClient.create = { _, _ in PreviewData.household }
        }

        await store.send(.submitCreate) {
            $0.working = true
        }
        await store.receive(\.createSucceeded) {
            $0.working = false
            $0.inviteReveal = PreviewData.household.inviteCode
            $0.path = .inviteReveal
        }
    }

    func testJoinFailureSurfacesError() async {
        struct Boom: Error {}
        var state = HouseholdSetupFeature.State()
        state.path = .join
        state.inviteCode = "BAD"
        let store = TestStore(initialState: state) {
            HouseholdSetupFeature()
        } withDependencies: {
            $0.householdClient.join = { _, _ in throw Boom() }
        }

        await store.send(.submitJoin) {
            $0.working = true
        }
        await store.receive(\.joinFailed) {
            $0.working = false
            $0.error = String(describing: Boom())
        }
    }
}
