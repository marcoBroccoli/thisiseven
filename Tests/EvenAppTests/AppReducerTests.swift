import AuthClient
import ComposableArchitecture
import EvenApp
import EvenCore
import XCTest

@MainActor
final class AppReducerTests: XCTestCase {
    func testBootWaitsForSplashBeforeLogin() async {
        let store = TestStore(initialState: AppReducer.State.booting()) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .signedOut }
        }

        await store.send(.view(.appStarted))
        await store.receive(\.bootstrapResponse) {
            $0 = .booting(.init(bootstrapResult: .signedOut))
        }
        await store.send(.view(.splashFinished)) {
            $0 = .login(.init())
        }
    }

    func testBootWaitsForSplashBeforeReady() async {
        let store = TestStore(initialState: AppReducer.State.booting()) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .ready }
        }

        await store.send(.view(.appStarted))
        await store.receive(\.bootstrapResponse) {
            $0 = .booting(.init(bootstrapResult: .ready))
        }
        await store.send(.view(.splashFinished)) {
            $0 = .ready(.init())
        }
    }

    func testBootSplashCanFinishBeforeBootstrap() async {
        let store = TestStore(initialState: AppReducer.State.booting()) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .needsHousehold(userId: PreviewData.adaId) }
        }

        await store.send(.view(.splashFinished)) {
            $0 = .booting(.init(splashFinished: true))
        }
        await store.send(.view(.appStarted))
        await store.receive(\.bootstrapResponse) {
            $0 = .householdSetup(.init())
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

    /// Leaving your last household leaves you signed in but homeless — the
    /// join-or-create door, not how-it-works and not the login screen.
    func testLeavingTheLastHouseholdRoutesBackToHouseholdSetup() async {
        let store = TestStore(initialState: AppReducer.State.ready(.init())) {
            AppReducer()
        }
        store.exhaustivity = .off

        await store.send(.ready(.delegate(.leftLastHousehold))) {
            $0 = .householdSetup(.init())
        }
    }
}
