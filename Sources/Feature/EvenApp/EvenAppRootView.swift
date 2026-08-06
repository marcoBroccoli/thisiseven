#if os(iOS)
    import ComposableArchitecture
    import ConnectionsFeature
    import Design
    import EvenCore
    import HouseholdSetupFeature
    import InboxFeature
    import LoginFeature
    import OnboardingFeature
    import SplashFeature
    import SwiftUI
    import TodayFeature

    /// TCA composition root — splash → login → onboarding → household → Today + Inbox.
    @ViewAction(for: AppReducer.self)
    public struct EvenAppRootView: View {
        @State public var store: StoreOf<AppReducer>

        public init(store: StoreOf<AppReducer> = Store(initialState: .booting) { AppReducer() }) {
            _store = State(initialValue: store)
        }

        public var body: some View {
            ZStack {
                EvenPaperBackground()

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
                .evenGrainOverlay()
            }
            .task {
                if EvenLaunchArguments.resetSession {
                    await SharedSession.store.signOut()
                }
                await send(.appStarted).finish()
            }
        }
    }

    #Preview("App · flow") {
        EvenAppRootView(store: EvenAppPreviewSupport.flow())
    }

    #Preview("App · booting") {
        EvenAppRootView(store: EvenAppPreviewSupport.booting())
    }

    #Preview("App · login") {
        EvenAppRootView(store: EvenAppPreviewSupport.login())
    }

    #Preview("App · onboarding") {
        EvenAppRootView(store: EvenAppPreviewSupport.onboarding())
    }

    #Preview("App · ready") {
        EvenAppRootView(store: EvenAppPreviewSupport.ready())
    }
#endif
