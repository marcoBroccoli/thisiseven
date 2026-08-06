#if os(watchOS)
    import ComposableArchitecture
    import ConnectionsFeature
    import HouseholdSetupFeature
    import InboxFeature
    import LoginFeature
    import OnboardingFeature
    import SplashFeature
    import SwiftUI
    import TodayFeature

    /// Placeholder composition root — product Watch UI stays in `ios/EvenWatch`.
    @ViewAction(for: AppReducer.self)
    public struct EvenAppRootView: View {
        @State public var store: StoreOf<AppReducer>

        public init(store: StoreOf<AppReducer> = Store(initialState: .booting) { AppReducer() }) {
            _store = State(initialValue: store)
        }

        public var body: some View {
            Group {
                switch store.state {
                case .booting:
                    BootSplashView()
                case .login:
                    if let store = store.scope(state: \.login, action: \.login) {
                        LoginView(store: store)
                    }
                case .onboarding:
                    if let store = store.scope(state: \.onboarding, action: \.onboarding) {
                        OnboardingView(store: store)
                    }
                case .householdSetup:
                    if let store = store.scope(state: \.householdSetup, action: \.householdSetup) {
                        HouseholdSetupView(store: store)
                    }
                case .connections:
                    if let store = store.scope(state: \.connections, action: \.connections) {
                        ConnectionsView(store: store)
                    }
                case .ready:
                    if let store = store.scope(state: \.ready, action: \.ready) {
                        MainTabView(store: store)
                    }
                }
            }
            .task {
                await send(.appStarted).finish()
            }
        }
    }
#endif
