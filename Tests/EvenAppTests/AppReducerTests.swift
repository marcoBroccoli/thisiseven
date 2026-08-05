import AuthClient
import ComposableArchitecture
import EvenApp
import XCTest

@MainActor
final class AppReducerTests: XCTestCase {
    func testBootRoutesSignedOutToOnboarding() async {
        let store = TestStore(initialState: AppReducer.State.booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .signedOut }
        }

        await store.send(.appStarted)
        await store.receive(\.bootstrapResponse) {
            $0 = .onboarding(.init())
        }
    }

    func testBootRoutesReadyToMain() async {
        let store = TestStore(initialState: AppReducer.State.booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .ready }
        }

        await store.send(.appStarted)
        await store.receive(\.bootstrapResponse) {
            $0 = .ready(.init())
        }
    }
}
