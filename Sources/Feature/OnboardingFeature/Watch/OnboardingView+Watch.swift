#if os(watchOS)
    import ComposableArchitecture
    import SwiftUI

    @ViewAction(for: OnboardingReducer.self)
    public struct OnboardingView: View {
        @Bindable public var store: StoreOf<OnboardingReducer>

        public init(store: StoreOf<OnboardingReducer>) {
            self.store = store
        }

        public var body: some View {
            Text("Onboarding")
        }
    }
#endif
