import ComposableArchitecture
import OnboardingFeature
import XCTest

@MainActor
final class OnboardingFeatureTests: XCTestCase {
    func testPagesAdvanceThenFinish() async {
        let store = TestStore(initialState: OnboardingReducer.State.weigh) {
            OnboardingReducer()
        }

        await store.send(.view(.nextTapped)) {
            $0 = .drafts
        }
        await store.send(.view(.nextTapped)) {
            $0 = .sunday
        }
        await store.send(.view(.nextTapped))
        await store.receive(\.delegate.finished)
    }

    func testBackStepsThroughPages() async {
        let store = TestStore(initialState: OnboardingReducer.State.sunday) {
            OnboardingReducer()
        }

        await store.send(.view(.backTapped)) {
            $0 = .drafts
        }
        await store.send(.view(.backTapped)) {
            $0 = .weigh
        }
        await store.send(.view(.backTapped))
    }

    func testSkipFinishesImmediately() async {
        let store = TestStore(initialState: OnboardingReducer.State.weigh) {
            OnboardingReducer()
        }

        await store.send(.view(.skipTapped))
        await store.receive(\.delegate.finished)
    }
}
