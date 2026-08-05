import AuthClient
import ComposableArchitecture
import EvenCore

public enum OnboardingPreviewSupport {
    public static func welcome() -> StoreOf<OnboardingFeature> {
        Store(initialState: OnboardingFeature.State(step: .welcome)) {
            OnboardingFeature()
        } withDependencies: {
            $0.authClient.signInWithApple = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
            $0.authClient.signInEmail = { _, _ in .needsHousehold(userId: PreviewData.adaId) }
        }
    }

    public static func howItWorks(page: Int = 1) -> StoreOf<OnboardingFeature> {
        var state = OnboardingFeature.State(step: .howItWorks)
        state.howItWorksPage = page
        return Store(initialState: state) {
            OnboardingFeature()
        }
    }
}
