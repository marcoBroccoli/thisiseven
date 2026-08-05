import AuthClient
import ComposableArchitecture
import EvenCore
import OnboardingFeature
import XCTest

@MainActor
final class OnboardingFeatureTests: XCTestCase {
    func testSignInNeedsHouseholdAdvancesToHowItWorks() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.authClient.signInEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
        }

        await store.send(.debugEmailSignIn(email: "a@b.c", password: "x")) {
            $0.working = true
            $0.error = nil
        }
        await store.receive(\.signInSucceeded) {
            $0.working = false
            $0.step = .howItWorks
            $0.howItWorksPage = 1
        }
    }

    func testHowItWorksPagesThenDelegatesNeedsHousehold() async {
        var state = OnboardingFeature.State(step: .howItWorks)
        state.howItWorksPage = 1
        let store = TestStore(initialState: state) {
            OnboardingFeature()
        }

        await store.send(.nextHowItWorks) {
            $0.howItWorksPage = 2
        }
        await store.send(.nextHowItWorks) {
            $0.howItWorksPage = 3
        }
        await store.send(.nextHowItWorks)
        await store.receive(\.delegate.needsHousehold)
    }
}
