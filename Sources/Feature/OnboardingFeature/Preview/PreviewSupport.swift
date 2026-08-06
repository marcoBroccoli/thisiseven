import ComposableArchitecture

@MainActor
public enum OnboardingPreviewSupport {
    public static func flow() -> StoreOf<OnboardingReducer> {
        Store(initialState: .weigh) {
            OnboardingReducer()
        }
    }
}
