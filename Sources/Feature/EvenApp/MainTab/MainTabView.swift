#if os(iOS)
    import ComposableArchitecture
    import Design
    import IGTabBar
    import InboxFeature
    import SwiftUI
    import TodayFeature

    @ViewAction(for: MainTabReducer.self)
    public struct MainTabView: View {
        @Bindable public var store: StoreOf<MainTabReducer>
        @State private var tabBarProgress: CGFloat = 0

        public init(store: StoreOf<MainTabReducer>) {
            self.store = store
        }

        public var body: some View {
            TabView(selection: $store.tab.sending(\.view.selectTab)) {
                TodayView(
                    store: store.scope(state: \.today, action: \.today),
                    tabBarProgress: $tabBarProgress
                )
                .hideNativeTabBar()
                .tag(MainTabReducer.State.Tab.today)

                InboxView(
                    store: store.scope(state: \.inbox, action: \.inbox),
                    tabBarProgress: $tabBarProgress
                )
                .hideNativeTabBar()
                .tag(MainTabReducer.State.Tab.inbox)
            }
            .tint(EvenTokens.espresso)
            .toolbarVisibility(.hidden, for: .tabBar)
            .overlay(alignment: .bottom) {
                IGStyleTabBar(
                    selection: $store.tab.sending(\.view.selectTab),
                    configuration: IGStyleTabBarConfiguration(
                        selectedSegmentTint: EvenTokens.espresso.opacity(0.14),
                        foreground: EvenTokens.espresso
                    ),
                    onInteraction: expandTabBar
                ) { tab in
                    switch tab {
                    case .today: .symbol("sun.max")
                    case .inbox: .symbol("tray")
                    }
                }
                .igTabBarChrome(progress: tabBarProgress, collapses: true)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Main tabs")
            }
            .task { await send(.appear).finish() }
        }

        private func expandTabBar() {
            guard tabBarProgress != 0 else { return }
            withAnimation(.interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0)) {
                tabBarProgress = 0
            }
        }
    }

    #Preview("Main tabs") {
        MainTabView(store: Store(initialState: MainTabReducer.State()) { MainTabReducer() })
    }
#endif
