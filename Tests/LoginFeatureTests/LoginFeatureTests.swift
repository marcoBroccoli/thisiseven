import AuthClient
import ComposableArchitecture
import EvenCore
import LoginFeature
import XCTest

@MainActor
final class LoginFeatureTests: XCTestCase {
    func testSignInNeedsHouseholdDelegates() async {
        let store = TestStore(initialState: LoginReducer.State()) {
            LoginReducer()
        } withDependencies: {
            $0.authClient.signInEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
        }

        await store.send(.view(.debugEmailSignIn(email: "a@b.c", password: "x"))) {
            $0.working = true
            $0.error = nil
        }
        await store.receive(\.signInSucceeded) {
            $0.working = false
        }
        await store.receive(\.delegate.needsHousehold)
    }

    func testSignInReadyDelegatesAlreadyReady() async {
        let store = TestStore(initialState: LoginReducer.State()) {
            LoginReducer()
        } withDependencies: {
            $0.authClient.signInEmail = { _, _ in .ready }
        }

        await store.send(.view(.debugEmailSignIn(email: "a@b.c", password: "x"))) {
            $0.working = true
            $0.error = nil
        }
        await store.receive(\.signInSucceeded) {
            $0.working = false
        }
        await store.receive(\.delegate.alreadyReady)
    }
}
