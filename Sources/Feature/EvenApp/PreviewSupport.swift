import AuthClient
import ComposableArchitecture
import EvenCore
import OnboardingFeature

public enum EvenAppPreviewSupport {
    public static func booting() -> StoreOf<AppReducer> {
        Store(initialState: .booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return .signedOut
            }
        }
    }

    public static func onboarding() -> StoreOf<AppReducer> {
        Store(initialState: .onboarding(OnboardingFeature.State())) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .signedOut }
        }
    }

    public static func ready() -> StoreOf<AppReducer> {
        Store(initialState: .ready(MainReducer.State())) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .ready }
        }
    }
}
