import AuthClient
import ComposableArchitecture
import EvenApp
import EvenCore
import XCTest

@MainActor
final class AppReducerTests: XCTestCase {
    func testBootRoutesSignedOutToLogin() async {
        let store = TestStore(initialState: AppReducer.State.booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .signedOut }
        }

        await store.send(.view(.appStarted))
        await store.receive(\.bootstrapResponse) {
            $0 = .login(.init())
        }
    }

    func testBootRoutesNeedsHouseholdToHouseholdSetup() async {
        let store = TestStore(initialState: AppReducer.State.booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .needsHousehold(userId: PreviewData.adaId) }
        }

        await store.send(.view(.appStarted))
        await store.receive(\.bootstrapResponse) {
            $0 = .householdSetup(.init())
        }
    }

    func testBootRoutesReadyToMain() async {
        let store = TestStore(initialState: AppReducer.State.booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .ready }
        }

        await store.send(.view(.appStarted))
        await store.receive(\.bootstrapResponse) {
            $0 = .ready(.init())
        }
    }

    func testLoginNeedsHouseholdRoutesToOnboarding() async {
        let store = TestStore(initialState: AppReducer.State.login(.init())) {
            AppReducer()
        }

        await store.send(.login(.delegate(.needsHousehold))) {
            $0 = .onboarding(.weigh)
        }
    }

    func testOnboardingFinishedRoutesToHouseholdSetup() async {
        let store = TestStore(initialState: AppReducer.State.onboarding(.weigh)) {
            AppReducer()
        }

        await store.send(.onboarding(.delegate(.finished))) {
            $0 = .householdSetup(.init())
        }
    }
}
