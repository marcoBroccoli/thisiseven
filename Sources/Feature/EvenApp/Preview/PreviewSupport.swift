import AuthClient
import ComposableArchitecture
import EvenCore
import LoginFeature
import OnboardingFeature

public enum EvenAppPreviewSupport {
    /// Boot → login → onboarding → household → connections → ready.
    public static func flow() -> StoreOf<AppReducer> {
        Store(initialState: .booting) {
            AppReducer()
        }
    }

    public static func booting(
        bootstrapLag: Duration = .seconds(2)
    ) -> StoreOf<AppReducer> {
        Store(initialState: .booting) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = {
                try? await PreviewDelay.delayed(bootstrapLag)()
                return .signedOut
            }
        }
    }

    public static func login() -> StoreOf<AppReducer> {
        Store(initialState: .login(LoginReducer.State())) {
            AppReducer()
        }
    }

    public static func onboarding() -> StoreOf<AppReducer> {
        Store(initialState: .onboarding(.weigh)) {
            AppReducer()
        }
    }

    public static func ready() -> StoreOf<AppReducer> {
        Store(initialState: .ready(MainTabReducer.State())) {
            AppReducer()
        } withDependencies: {
            $0.authClient.bootstrap = { .ready }
        }
    }
}
